# frozen_string_literal: true

require "net/http"
require "uri"
require "json"
require "securerandom"

module Strands
  module Models
    # Google Gemini model provider implementation.
    #
    # Implements the streaming interface using the Gemini API with
    # Server-Sent Events (SSE) for streaming responses via
    # +streamGenerateContent+.
    #
    # @example Basic usage
    #   model = Strands::Models::Gemini.new(
    #     model_id: "gemini-1.5-pro",
    #     api_key: ENV["GEMINI_API_KEY"]
    #   )
    #   model.stream(messages) { |event| process(event) }
    #
    class Gemini
      include Base
      include StreamEventBuilder

      # Default Gemini API base URL
      DEFAULT_BASE_URL = "https://generativelanguage.googleapis.com"

      # Context overflow error messages from Gemini
      CONTEXT_OVERFLOW_MESSAGES = [
        "exceeds the maximum number of tokens",
        "request is too large",
        "content is too long",
        "prompt is too long"
      ].freeze

      # @return [Hash] the model configuration
      attr_reader :config

      # Initialize the Gemini model provider.
      #
      # @param model_id [String] the model identifier (e.g., "gemini-1.5-pro")
      # @param api_key [String, nil] Gemini API key (defaults to ENV["GEMINI_API_KEY"])
      # @param params [Hash] additional model parameters (temperature, maxOutputTokens, etc.)
      def initialize(model_id:, api_key: nil, **params)
        @config = {
          model_id: model_id,
          api_key: api_key || ENV.fetch("GEMINI_API_KEY", nil),
          params: params
        }
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
      # @return [String]
      def inspect
        "#<#{self.class} model_id=#{@config[:model_id].inspect}>"
      end

      # Stream a conversation with the Gemini model.
      #
      # Formats the request, sends it to the Gemini API with SSE streaming,
      # parses chunks into StreamEvent objects, and yields them.
      #
      # @param messages [Array<Hash>] conversation messages
      # @param system_prompt [String, nil] system prompt
      # @param tools [Array<Strands::Types::Tools::ToolSpec>, nil] available tools
      # @param tool_choice [Object, nil] tool selection strategy
      # @param kwargs [Hash] additional parameters
      # @yieldparam event [Strands::Types::Streaming::StreamEvent] a stream event
      # @return [void]
      # @raise [Strands::Types::Exceptions::ContextWindowOverflowError] if input exceeds context
      # @raise [Strands::Types::Exceptions::ModelThrottledError] if rate limited
      def stream(messages, system_prompt: nil, tools: nil, tool_choice: nil, **kwargs)
        request_body = format_request(messages, system_prompt: system_prompt, tools: tools, tool_choice: tool_choice)

        model_id = @config[:model_id]
        api_key = @config[:api_key]
        uri = URI("#{DEFAULT_BASE_URL}/v1beta/models/#{model_id}:streamGenerateContent?alt=sse&key=#{api_key}")

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = (uri.scheme == "https")
        http.read_timeout = 300

        request = Net::HTTP::Post.new("#{uri.path}?#{uri.query}")
        request["Content-Type"] = "application/json"
        request.body = JSON.generate(request_body)

        function_calls = []
        has_text = false

        http.request(request) do |response|
          handle_error_response(response) unless response.is_a?(Net::HTTPSuccess)

          yield build_stream_event(:message_start, role: :assistant)

          content_started = false
          buffer = +""

          response.read_body do |chunk|
            buffer << chunk
            while (line_end = buffer.index("\n"))
              line = buffer.slice!(0, line_end + 1).strip
              next if line.empty?
              next unless line.start_with?("data: ")

              data = line[6..]
              next if data == "[DONE]"

              parsed = begin
                JSON.parse(data, symbolize_names: true)
              rescue JSON::ParserError
                next
              end

              candidates = parsed[:candidates] || []
              next if candidates.empty?

              candidate = candidates[0]
              content = candidate[:content] || {}
              parts = content[:parts] || []

              parts.each do |part|
                if part[:text]
                  unless content_started
                    yield build_stream_event(:content_block_start, start: Types::Streaming::ContentBlockStart.new)
                    content_started = true
                  end
                  has_text = true
                  yield build_stream_event(:content_block_delta,
                                           delta: Types::Streaming::ContentBlockDelta.new(text: part[:text]))
                end

                if part[:functionCall]
                  function_calls << part[:functionCall]
                end
              end

              # Check for finish reason
              if candidate[:finishReason]
                finish_reason = candidate[:finishReason]
              end

              # Handle usage metadata
              if parsed[:usageMetadata]
                usage = parsed[:usageMetadata]
                yield build_stream_event(:metadata,
                                         usage: Types::EventLoop::Usage.new(
                                           input_tokens: usage[:promptTokenCount] || 0,
                                           output_tokens: usage[:candidatesTokenCount] || 0,
                                           total_tokens: usage[:totalTokenCount]
                                         ),
                                         metrics: Types::EventLoop::Metrics.new(latency_ms: 0))
              end
            end
          end

          # Close content block if open
          yield build_stream_event(:content_block_stop) if content_started

          # Emit tool use blocks
          function_calls.each do |fc|
            tool_use_id = SecureRandom.uuid
            tool_use_start = Types::Streaming::ContentBlockStart.new(
              tool_use: Types::Streaming::ContentBlockStartToolUse.new(
                name: fc[:name],
                tool_use_id: tool_use_id
              )
            )
            yield build_stream_event(:content_block_start, start: tool_use_start)

            input = fc[:args].is_a?(String) ? fc[:args] : JSON.generate(fc[:args] || {})
            yield build_stream_event(:content_block_delta,
                                     delta: Types::Streaming::ContentBlockDelta.new(
                                       tool_use: Types::Streaming::ContentBlockDeltaToolUse.new(
                                         input: input
                                       )
                                     ))

            yield build_stream_event(:content_block_stop)
          end

          # Determine stop reason
          stop_reason = map_finish_reason(finish_reason, function_calls)
          yield build_stream_event(:message_stop, stop_reason: stop_reason)
        end
      end

      # Format the request body for the Gemini API.
      #
      # @param messages [Array<Hash>] conversation messages
      # @param system_prompt [String, nil] system prompt
      # @param tools [Array, nil] available tools
      # @param tool_choice [Object, nil] tool selection strategy
      # @return [Hash] the formatted request body
      def format_request(messages, system_prompt: nil, tools: nil, tool_choice: nil)
        request = {}

        # System instruction
        if system_prompt
          request[:systemInstruction] = { parts: [{ text: system_prompt }] }
        end

        # Format contents
        request[:contents] = messages.map { |msg| format_message(msg) }

        # Add tools
        if tools && !tools.empty?
          request[:tools] = [{ functionDeclarations: tools.map { |t| format_tool_spec(t) } }]
        end

        # Generation config
        generation_config = {}
        params = @config[:params] || {}
        generation_config[:temperature] = params[:temperature] if params[:temperature]
        generation_config[:maxOutputTokens] = params[:max_tokens] if params[:max_tokens]
        generation_config[:topP] = params[:top_p] if params[:top_p]
        generation_config[:topK] = params[:top_k] if params[:top_k]
        request[:generationConfig] = generation_config unless generation_config.empty?

        request
      end

      private

      # Format a single message into Gemini Content format.
      #
      # @param msg [Hash] a message with :role and :content keys
      # @return [Hash] Gemini-compatible content object
      def format_message(msg)
        role = msg[:role].to_s == "assistant" ? "model" : "user"
        content = msg[:content]

        if content.is_a?(String)
          return { role: role, parts: [{ text: content }] }
        end

        parts = []
        Array(content).each do |block|
          next unless block.is_a?(Hash)

          if block[:text]
            parts << { text: block[:text] }
          elsif block[:tool_use]
            tu = block[:tool_use]
            parts << {
              functionCall: {
                name: tu[:name],
                args: tu[:input] || {}
              }
            }
          elsif block[:tool_result]
            tr = block[:tool_result]
            result_content = Array(tr[:content]).map do |c|
              if c[:text]
                c[:text]
              elsif c[:json]
                JSON.generate(c[:json])
              else
                c.to_s
              end
            end.join("\n")
            parts << {
              functionResponse: {
                name: tr[:name] || "function",
                response: { result: result_content }
              }
            }
          end
        end

        { role: role, parts: parts.empty? ? [{ text: "" }] : parts }
      end

      # Format a ToolSpec into Gemini function declaration format.
      #
      # @param tool [Strands::Types::Tools::ToolSpec, Hash] the tool specification
      # @return [Hash] Gemini-compatible function declaration
      def format_tool_spec(tool)
        if tool.is_a?(Types::Tools::ToolSpec)
          {
            name: tool.name,
            description: tool.description,
            parameters: tool.input_schema
          }
        else
          {
            name: tool[:name],
            description: tool[:description],
            parameters: tool[:input_schema]
          }
        end
      end

      # Map Gemini finishReason to SDK stop_reason symbol.
      #
      # @param finish_reason [String, nil] the Gemini finish reason
      # @param function_calls [Array] any function calls collected
      # @return [Symbol] the SDK stop reason
      def map_finish_reason(finish_reason, function_calls = [])
        return :tool_use unless function_calls.empty?

        case finish_reason
        when "STOP"
          :end_turn
        when "MAX_TOKENS"
          :max_tokens
        when "SAFETY"
          :content_filtered
        else
          :end_turn
        end
      end

      # Handle non-success HTTP responses from Gemini.
      #
      # @param response [Net::HTTPResponse] the error response
      # @raise [Strands::Types::Exceptions::ContextWindowOverflowError]
      # @raise [Strands::Types::Exceptions::ModelThrottledError]
      # @raise [Strands::Error]
      def handle_error_response(response)
        body = begin
          JSON.parse(response.body, symbolize_names: true)
        rescue StandardError
          { error: { message: response.body } }
        end

        error_message = body.dig(:error, :message) || response.body.to_s

        case response.code.to_i
        when 429
          raise Types::Exceptions::ModelThrottledError, error_message
        when 400
          if CONTEXT_OVERFLOW_MESSAGES.any? { |msg| error_message.downcase.include?(msg) }
            raise Types::Exceptions::ContextWindowOverflowError, error_message
          end
          raise Strands::Error, "Gemini API error (400): #{error_message}"
        else
          if CONTEXT_OVERFLOW_MESSAGES.any? { |msg| error_message.downcase.include?(msg) }
            raise Types::Exceptions::ContextWindowOverflowError, error_message
          end
          raise Strands::Error, "Gemini API error (#{response.code}): #{error_message}"
        end
      end
    end
  end
end
