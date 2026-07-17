# frozen_string_literal: true

require "net/http"
require "uri"
require "json"
require "openssl"
require "time"

module Strands
  module Models
    # AWS Bedrock model provider implementation.
    #
    # Implements the streaming interface using the AWS Bedrock Converse Stream API.
    # Uses AWS Signature V4 authentication via net/http (no external gems required).
    # If the aws-sdk-bedrockruntime gem is available, it will use the SDK client instead.
    #
    # @example Basic usage with credentials
    #   model = Strands::Models::Bedrock.new(
    #     model_id: "anthropic.claude-3-5-sonnet-20241022-v2:0",
    #     region: "us-west-2"
    #   )
    #   model.stream(messages) { |event| process(event) }
    #
    # @example Using the default model
    #   # model_id defaults to Bedrock::DEFAULT_BEDROCK_MODEL_ID with a warning.
    #   # Pass model_id explicitly to pin behavior across releases.
    #   model = Strands::Models::Bedrock.new
    #
    class Bedrock
      include Base
      include StreamEventBuilder

      # Default AWS region for Bedrock
      DEFAULT_REGION = "us-west-2"

      # Default Bedrock model ID used when no model_id is specified.
      # Subject to change between releases -- pass model_id explicitly to pin behavior.
      DEFAULT_BEDROCK_MODEL_ID = "global.anthropic.claude-sonnet-4-6"

      # Context overflow error messages from Bedrock
      CONTEXT_OVERFLOW_MESSAGES = [
        "Input is too long for requested model",
        "input length and `max_tokens` exceed context limit",
        "too many total text bytes",
        "prompt is too long"
      ].freeze

      # @return [Hash] the model configuration
      attr_reader :config

      # Initialize the Bedrock model provider.
      #
      # @param model_id [String, nil] the Bedrock model identifier. Defaults to
      #   {DEFAULT_BEDROCK_MODEL_ID} (a moving target across releases) with a warning;
      #   pass an explicit model_id to pin behavior.
      # @param region [String] AWS region (defaults to ENV["AWS_REGION"] or "us-west-2")
      # @param access_key_id [String, nil] AWS access key ID
      # @param secret_access_key [String, nil] AWS secret access key
      # @param session_token [String, nil] AWS session token (for temporary credentials)
      # @param params [Hash] additional model parameters (max_tokens, temperature, etc.)
      def initialize(model_id: nil, region: nil, access_key_id: nil, secret_access_key: nil, session_token: nil,
                      **params)
        @config = {
          model_id: model_id || default_model_id_with_warning,
          region: region || ENV.fetch("AWS_REGION", ENV.fetch("AWS_DEFAULT_REGION", DEFAULT_REGION)),
          access_key_id: access_key_id || ENV.fetch("AWS_ACCESS_KEY_ID", nil),
          secret_access_key: secret_access_key || ENV.fetch("AWS_SECRET_ACCESS_KEY", nil),
          session_token: session_token || ENV.fetch("AWS_SESSION_TOKEN", nil),
          params: params
        }

        # Attempt to load AWS SDK if available
        @use_sdk = false
        begin
          require "aws-sdk-bedrockruntime"
          @use_sdk = true
        rescue LoadError
          # AWS SDK not available, will use HTTP client
        end
      end

      # Update the model configuration.
      #
      # @param opts [Hash] configuration options to merge
      # @return [void]
      def update_config(**opts)
        @config.merge!(opts)
      end

      # Return a copy of the current configuration.
      #
      # @return [Hash] the model configuration
      def get_config
        @config.dup
      end

      # Returns a string representation with sensitive values redacted.
      #
      # Prevents AWS credentials and secrets from leaking into logs, error reports,
      # or debugging output.
      #
      # @return [String]
      def inspect
        "#<#{self.class} model_id=#{@config[:model_id].inspect} region=#{@config[:region].inspect}>"
      end

      # Stream a conversation with the Bedrock model.
      #
      # @param messages [Array<Hash>] conversation messages
      # @param system_prompt [String, nil] system prompt
      # @param tools [Array<Strands::Types::Tools::ToolSpec>, nil] available tools
      # @param tool_choice [Object, nil] tool selection strategy
      # @param kwargs [Hash] additional parameters
      # @yieldparam event [Strands::Types::Streaming::StreamEvent] a stream event
      # @return [void]
      # @raise [Strands::Types::Exceptions::ContextWindowOverflowError] if input exceeds context window
      # @raise [Strands::Types::Exceptions::ModelThrottledError] if rate limited
      def stream(messages, system_prompt: nil, tools: nil, tool_choice: nil, **kwargs)
        if @use_sdk
          stream_with_sdk(messages, system_prompt: system_prompt, tools: tools, tool_choice: tool_choice, **kwargs) do |event|
            yield event
          end
        else
          stream_with_http(messages, system_prompt: system_prompt, tools: tools, tool_choice: tool_choice, **kwargs) do |event|
            yield event
          end
        end
      end

      private

      # Returns the default Bedrock model ID and warns that it is subject to change.
      #
      # Mirrors the behavior of the Python and TypeScript SDKs: when no model_id is
      # provided, fall back to a default and emit a one-time warning so callers know
      # to pin an explicit model_id for stable behavior across releases.
      #
      # @return [String] the default model ID
      def default_model_id_with_warning
        Kernel.warn(
          "model_id=<#{DEFAULT_BEDROCK_MODEL_ID}> | using default modelId, which is subject to change | " \
          "set model_id explicitly to pin the value",
          uplevel: 1
        )
        DEFAULT_BEDROCK_MODEL_ID
      end

      # Stream using the AWS SDK (if available).
      #
      # @param messages [Array<Hash>] conversation messages
      # @param system_prompt [String, nil] system prompt
      # @param tools [Array, nil] available tools
      # @param tool_choice [Object, nil] tool selection strategy
      # @param kwargs [Hash] additional parameters
      # @yieldparam event [Strands::Types::Streaming::StreamEvent]
      def stream_with_sdk(messages, system_prompt: nil, tools: nil, tool_choice: nil, **kwargs)
        client = Aws::BedrockRuntime::Client.new(
          region: @config[:region],
          access_key_id: @config[:access_key_id],
          secret_access_key: @config[:secret_access_key],
          session_token: @config[:session_token]
        )

        request_params = format_converse_request(messages, system_prompt: system_prompt, tools: tools,
                                                           tool_choice: tool_choice)

        begin
          handler = StreamEventHandler.new { |event| yield event }
          client.converse_stream(request_params, event_stream_handler: handler)
        rescue Aws::BedrockRuntime::Errors::ThrottlingException => e
          raise Types::Exceptions::ModelThrottledError, e.message
        rescue Aws::BedrockRuntime::Errors::ValidationException => e
          if CONTEXT_OVERFLOW_MESSAGES.any? { |msg| e.message.include?(msg) }
            raise Types::Exceptions::ContextWindowOverflowError, e.message
          end
          raise Strands::Error, "Bedrock validation error: #{e.message}"
        end
      end

      # Stream using raw HTTP with AWS Signature V4 signing.
      #
      # @param messages [Array<Hash>] conversation messages
      # @param system_prompt [String, nil] system prompt
      # @param tools [Array, nil] available tools
      # @param tool_choice [Object, nil] tool selection strategy
      # @param kwargs [Hash] additional parameters
      # @yieldparam event [Strands::Types::Streaming::StreamEvent]
      def stream_with_http(messages, system_prompt: nil, tools: nil, tool_choice: nil, **kwargs)
        request_body = format_converse_request(messages, system_prompt: system_prompt, tools: tools,
                                                         tool_choice: tool_choice)
        model_id = @config[:model_id]
        region = @config[:region]
        host = "bedrock-runtime.#{region}.amazonaws.com"
        path = "/model/#{model_id}/converse-stream"

        uri = URI("https://#{host}#{path}")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.read_timeout = 300

        body = JSON.generate(request_body)
        headers = sign_request("POST", uri, body, host, region)

        request = Net::HTTP::Post.new(uri.path)
        headers.each { |k, v| request[k] = v }
        request["Content-Type"] = "application/json"
        request.body = body

        http.request(request) do |response|
          handle_error_response(response) unless response.is_a?(Net::HTTPSuccess)
          parse_event_stream(response) { |event| yield event }
        end
      end

      # Format the request for Bedrock ConverseStream API.
      #
      # @param messages [Array<Hash>] conversation messages
      # @param system_prompt [String, nil] system prompt
      # @param tools [Array, nil] available tools
      # @param tool_choice [Object, nil] tool selection strategy
      # @return [Hash] the formatted Bedrock request
      def format_converse_request(messages, system_prompt: nil, tools: nil, tool_choice: nil)
        request = {
          modelId: @config[:model_id],
          messages: format_messages(messages)
        }

        if system_prompt
          request[:system] = [{ text: system_prompt }]
        end

        if tools && !tools.empty?
          tool_config = { tools: tools.map { |t| format_tool(t) } }
          if tool_choice
            tool_config[:toolChoice] = format_tool_choice(tool_choice)
          end
          request[:toolConfig] = tool_config
        end

        # Merge inference config from params
        if @config[:params] && !@config[:params].empty?
          request[:inferenceConfig] = @config[:params]
        end

        request
      end

      # Format messages for the Bedrock API.
      #
      # @param messages [Array<Hash>] raw messages
      # @return [Array<Hash>] formatted Bedrock messages
      def format_messages(messages)
        messages.map do |msg|
          {
            role: msg[:role].to_s,
            content: format_content_blocks(msg[:content])
          }
        end
      end

      # Format content blocks for Bedrock.
      #
      # @param content [Array, String] content blocks or plain text
      # @return [Array<Hash>] formatted content blocks
      def format_content_blocks(content)
        return [{ text: content }] if content.is_a?(String)

        Array(content).map do |block|
          if block.is_a?(Hash)
            if block[:text]
              { text: block[:text] }
            elsif block[:tool_use]
              tu = block[:tool_use]
              { toolUse: { toolUseId: tu[:tool_use_id], name: tu[:name], input: tu[:input] } }
            elsif block[:tool_result]
              tr = block[:tool_result]
              { toolResult: { toolUseId: tr[:tool_use_id], content: format_tool_result_content(tr[:content]),
                              status: (tr[:status] || :success).to_s } }
            elsif block[:image]
              { image: block[:image] }
            else
              { text: block.to_s }
            end
          else
            { text: block.to_s }
          end
        end
      end

      # Format tool result content for Bedrock.
      #
      # @param content [Array] tool result content blocks
      # @return [Array<Hash>] formatted content
      def format_tool_result_content(content)
        Array(content).map do |c|
          if c[:text]
            { text: c[:text] }
          elsif c[:json]
            { json: c[:json] }
          else
            { text: c.to_s }
          end
        end
      end

      # Format a tool spec for Bedrock.
      #
      # @param tool [Strands::Types::Tools::ToolSpec, Hash] tool specification
      # @return [Hash] Bedrock-formatted tool
      def format_tool(tool)
        if tool.is_a?(Types::Tools::ToolSpec)
          {
            toolSpec: {
              name: tool.name,
              description: tool.description,
              inputSchema: { json: tool.input_schema }
            }
          }
        else
          {
            toolSpec: {
              name: tool[:name],
              description: tool[:description],
              inputSchema: { json: tool[:input_schema] }
            }
          }
        end
      end

      # Format tool choice for Bedrock.
      #
      # @param choice [Object] tool choice config
      # @return [Hash] Bedrock tool choice
      def format_tool_choice(choice)
        case choice
        when Types::Tools::ToolChoiceAuto
          { auto: {} }
        when Types::Tools::ToolChoiceAny
          { any: {} }
        when Types::Tools::ToolChoiceTool
          { tool: { name: choice.name } }
        when Hash
          choice
        else
          { auto: {} }
        end
      end

      # Parse a Bedrock event stream response and yield StreamEvents.
      #
      # @param response [Net::HTTPResponse] the HTTP response with event stream
      # @yieldparam event [Strands::Types::Streaming::StreamEvent]
      def parse_event_stream(response)
        buffer = +""
        response.read_body do |chunk|
          buffer << chunk
          # Bedrock uses a binary event stream protocol.
          # For simplicity in the HTTP path, we parse JSON event boundaries.
          while (event_data = extract_json_event(buffer))
            stream_event = parse_bedrock_event(event_data)
            yield stream_event if stream_event
          end
        end
      end

      # Extract a JSON event from the binary event stream buffer.
      #
      # @param buffer [String] the binary buffer
      # @return [Hash, nil] parsed JSON event or nil if incomplete
      def extract_json_event(buffer)
        # Look for JSON objects in the buffer (simplified parsing)
        start_idx = buffer.index("{")
        return nil unless start_idx

        depth = 0
        idx = start_idx
        while idx < buffer.length
          case buffer[idx]
          when "{"
            depth += 1
          when "}"
            depth -= 1
            if depth.zero?
              json_str = buffer.slice!(0, idx + 1)
              json_str = json_str[start_idx..]
              return JSON.parse(json_str, symbolize_names: true)
            end
          end
          idx += 1
        end
        nil
      rescue JSON::ParserError
        buffer.clear
        nil
      end

      # Parse a Bedrock event into a StreamEvent.
      #
      # @param event [Hash] the parsed event data
      # @return [Strands::Types::Streaming::StreamEvent, nil]
      def parse_bedrock_event(event)
        if event[:messageStart]
          build_stream_event(:message_start, role: (event[:messageStart][:role] || "assistant").to_sym)
        elsif event[:contentBlockStart]
          start_data = event[:contentBlockStart][:start]
          start = if start_data && start_data[:toolUse]
                    Types::Streaming::ContentBlockStart.new(
                      tool_use: Types::Streaming::ContentBlockStartToolUse.new(
                        name: start_data[:toolUse][:name],
                        tool_use_id: start_data[:toolUse][:toolUseId]
                      )
                    )
                  else
                    Types::Streaming::ContentBlockStart.new
                  end
          build_stream_event(:content_block_start, start: start)
        elsif event[:contentBlockDelta]
          delta_data = event[:contentBlockDelta][:delta]
          delta = if delta_data[:text]
                    Types::Streaming::ContentBlockDelta.new(text: delta_data[:text])
                  elsif delta_data[:toolUse]
                    Types::Streaming::ContentBlockDelta.new(
                      tool_use: Types::Streaming::ContentBlockDeltaToolUse.new(
                        input: delta_data[:toolUse][:input]
                      )
                    )
                  else
                    Types::Streaming::ContentBlockDelta.new
                  end
          build_stream_event(:content_block_delta, delta: delta)
        elsif event[:contentBlockStop]
          build_stream_event(:content_block_stop)
        elsif event[:messageStop]
          stop_reason = (event[:messageStop][:stopReason] || "end_turn").to_sym
          build_stream_event(:message_stop, stop_reason: stop_reason)
        elsif event[:metadata]
          usage_data = event[:metadata][:usage]
          usage = if usage_data
                    Types::EventLoop::Usage.new(
                      input_tokens: usage_data[:inputTokens] || 0,
                      output_tokens: usage_data[:outputTokens] || 0
                    )
                  end
          metrics_data = event[:metadata][:metrics]
          metrics = if metrics_data
                      Types::EventLoop::Metrics.new(latency_ms: metrics_data[:latencyMs] || 0)
                    end
          build_stream_event(:metadata, usage: usage, metrics: metrics)
        end
      end

      # Sign an AWS request using Signature V4.
      #
      # @param method [String] HTTP method
      # @param uri [URI] request URI
      # @param body [String] request body
      # @param host [String] host header value
      # @param region [String] AWS region
      # @return [Hash] signed headers
      def sign_request(method, uri, body, host, region)
        service = "bedrock"
        now = Time.now.utc
        datestamp = now.strftime("%Y%m%d")
        amz_date = now.strftime("%Y%m%dT%H%M%SZ")

        credential_scope = "#{datestamp}/#{region}/#{service}/aws4_request"
        access_key = @config[:access_key_id]
        secret_key = @config[:secret_access_key]

        headers = {
          "Host" => host,
          "X-Amz-Date" => amz_date,
          "Content-Type" => "application/json"
        }

        if @config[:session_token]
          headers["X-Amz-Security-Token"] = @config[:session_token]
        end

        signed_headers = headers.keys.map(&:downcase).sort.join(";")
        canonical_headers = headers.keys.sort_by(&:downcase).map { |k| "#{k.downcase}:#{headers[k].strip}\n" }.join

        payload_hash = OpenSSL::Digest::SHA256.hexdigest(body)
        canonical_request = [
          method,
          uri.path,
          uri.query || "",
          canonical_headers,
          signed_headers,
          payload_hash
        ].join("\n")

        string_to_sign = [
          "AWS4-HMAC-SHA256",
          amz_date,
          credential_scope,
          OpenSSL::Digest::SHA256.hexdigest(canonical_request)
        ].join("\n")

        signing_key = get_signature_key(secret_key, datestamp, region, service)
        signature = OpenSSL::HMAC.hexdigest("SHA256", signing_key, string_to_sign)

        headers["Authorization"] = "AWS4-HMAC-SHA256 Credential=#{access_key}/#{credential_scope}, " \
                                   "SignedHeaders=#{signed_headers}, Signature=#{signature}"

        headers
      end

      # Derive the signing key for AWS Signature V4.
      #
      # @param key [String] secret access key
      # @param date_stamp [String] date in YYYYMMDD format
      # @param region [String] AWS region
      # @param service [String] AWS service name
      # @return [String] derived signing key
      def get_signature_key(key, date_stamp, region, service)
        k_date = OpenSSL::HMAC.digest("SHA256", "AWS4#{key}", date_stamp)
        k_region = OpenSSL::HMAC.digest("SHA256", k_date, region)
        k_service = OpenSSL::HMAC.digest("SHA256", k_region, service)
        OpenSSL::HMAC.digest("SHA256", k_service, "aws4_request")
      end

      # Handle non-success HTTP responses from Bedrock.
      #
      # @param response [Net::HTTPResponse] the error response
      # @raise [Strands::Types::Exceptions::ContextWindowOverflowError]
      # @raise [Strands::Types::Exceptions::ModelThrottledError]
      # @raise [Strands::Error]
      def handle_error_response(response)
        body = begin
          JSON.parse(response.body, symbolize_names: true)
        rescue StandardError
          { message: response.body }
        end

        error_message = body[:message] || response.body.to_s

        case response.code.to_i
        when 429
          raise Types::Exceptions::ModelThrottledError, error_message
        when 400
          if CONTEXT_OVERFLOW_MESSAGES.any? { |msg| error_message.include?(msg) }
            raise Types::Exceptions::ContextWindowOverflowError, error_message
          end
          raise Strands::Error, "Bedrock API error (400): #{error_message}"
        else
          if CONTEXT_OVERFLOW_MESSAGES.any? { |msg| error_message.include?(msg) }
            raise Types::Exceptions::ContextWindowOverflowError, error_message
          end
          raise Strands::Error, "Bedrock API error (#{response.code}): #{error_message}"
        end
      end

      # AWS SDK event stream handler (used when aws-sdk-bedrockruntime is available).
      class StreamEventHandler
        def initialize(&block)
          @callback = block
        end

        def on_message_start_event(event)
          @callback.call(
            Types::Streaming::StreamEvent.new(
              message_start: Types::Streaming::MessageStartEvent.new(role: :assistant)
            )
          )
        end

        def on_content_block_start_event(event)
          start = if event.content_block_start&.tool_use
                    Types::Streaming::ContentBlockStart.new(
                      tool_use: Types::Streaming::ContentBlockStartToolUse.new(
                        name: event.content_block_start.tool_use.name,
                        tool_use_id: event.content_block_start.tool_use.tool_use_id
                      )
                    )
                  else
                    Types::Streaming::ContentBlockStart.new
                  end
          @callback.call(
            Types::Streaming::StreamEvent.new(
              content_block_start: Types::Streaming::ContentBlockStartEvent.new(start: start)
            )
          )
        end

        def on_content_block_delta_event(event)
          delta_data = event.content_block_delta&.delta
          delta = if delta_data.respond_to?(:text) && delta_data.text
                    Types::Streaming::ContentBlockDelta.new(text: delta_data.text)
                  elsif delta_data.respond_to?(:tool_use) && delta_data.tool_use
                    Types::Streaming::ContentBlockDelta.new(
                      tool_use: Types::Streaming::ContentBlockDeltaToolUse.new(
                        input: delta_data.tool_use.input
                      )
                    )
                  else
                    Types::Streaming::ContentBlockDelta.new
                  end
          @callback.call(
            Types::Streaming::StreamEvent.new(
              content_block_delta: Types::Streaming::ContentBlockDeltaEvent.new(delta: delta)
            )
          )
        end

        def on_content_block_stop_event(_event)
          @callback.call(
            Types::Streaming::StreamEvent.new(
              content_block_stop: Types::Streaming::ContentBlockStopEvent.new
            )
          )
        end

        def on_message_stop_event(event)
          stop_reason = (event.message_stop&.stop_reason || "end_turn").to_sym
          @callback.call(
            Types::Streaming::StreamEvent.new(
              message_stop: Types::Streaming::MessageStopEvent.new(stop_reason: stop_reason)
            )
          )
        end

        def on_metadata_event(event)
          usage = if event.metadata&.usage
                    Types::EventLoop::Usage.new(
                      input_tokens: event.metadata.usage.input_tokens || 0,
                      output_tokens: event.metadata.usage.output_tokens || 0
                    )
                  end
          metrics = if event.metadata&.metrics
                      Types::EventLoop::Metrics.new(latency_ms: event.metadata.metrics.latency_ms || 0)
                    end
          @callback.call(
            Types::Streaming::StreamEvent.new(
              metadata: Types::Streaming::MetadataEvent.new(usage: usage, metrics: metrics)
            )
          )
        end
      end
    end
  end
end
