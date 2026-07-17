# frozen_string_literal: true

require "net/http"
require "uri"
require "json"
require "securerandom"

module Strands
  module Models
    # Mistral AI model provider implementation.
    #
    # Implements the streaming interface using the Mistral Chat Completions API
    # with Server-Sent Events (SSE) for streaming responses.
    #
    # @example Basic usage
    #   model = Strands::Models::Mistral.new(
    #     model_id: "mistral-large-latest",
    #     api_key: ENV["MISTRAL_API_KEY"]
    #   )
    #   model.stream(messages) { |event| process(event) }
    #
    class Mistral
      include Base
      include StreamEventBuilder

      # Default Mistral API base URL
      DEFAULT_BASE_URL = "https://api.mistral.ai"

      # Context overflow error messages from Mistral
      CONTEXT_OVERFLOW_MESSAGES = [
        "context_length_exceeded",
        "too many tokens",
        "input is too long"
      ].freeze

      # @return [Hash] the model configuration
      attr_reader :config

      # Initialize the Mistral model provider.
      #
      # @param model_id [String] the model identifier (e.g., "mistral-large-latest")
      # @param api_key [String, nil] Mistral API key (defaults to ENV["MISTRAL_API_KEY"])
      # @param base_url [String] API base URL
      # @param params [Hash] additional model parameters (temperature must be 0.0-1.0)
      # @raise [ArgumentError] if temperature is outside 0.0-1.0 range
      def initialize(model_id:, api_key: nil, base_url: DEFAULT_BASE_URL, **params)
        if params[:temperature] && (params[:temperature] < 0.0 || params[:temperature] > 1.0)
          raise ArgumentError, "temperature must be between 0.0 and 1.0, got #{params[:temperature]}"
        end

        @config = {
          model_id: model_id,
          api_key: api_key || ENV.fetch("MISTRAL_API_KEY", nil),
          base_url: base_url,
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
        "#<#{self.class} model_id=#{@config[:model_id].inspect} base_url=#{@config[:base_url].inspect}>"
      end

      # Stream a conversation with the Mistral model.
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

        uri = URI.join(@config[:base_url], "/v1/chat/completions")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = (uri.scheme == "https")
        http.read_timeout = 300

        request = Net::HTTP::Post.new(uri.path)
        request["Content-Type"] = "application/json"
        request["Authorization"] = "Bearer #{@config[:api_key]}"
        request.body = JSON.generate(request_body)

        tool_calls = {}
        current_data_type = nil
        finish_reason = nil

        http.request(request) do |response|
          handle_error_response(response) unless response.is_a?(Net::HTTPSuccess)

          yield build_stream_event(:message_start, role: :assistant)

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

              choices = parsed[:choices] || []
              next if choices.empty?

              choice = choices[0]
              delta = choice[:delta] || {}

              if delta[:content]
                if current_data_type != :text
                  yield build_stream_event(:content_block_stop) if current_data_type
                  yield build_stream_event(:content_block_start, start: Types::Streaming::ContentBlockStart.new)
                  current_data_type = :text
                end
                yield build_stream_event(:content_block_delta,
                                         delta: Types::Streaming::ContentBlockDelta.new(text: delta[:content]))
              end

              if delta[:tool_calls]
                delta[:tool_calls].each do |tc|
                  index = tc[:index]
                  tool_calls[index] ||= { id: nil, name: nil, arguments: +"" }
                  tool_calls[index][:id] = tc[:id] if tc[:id]
                  if tc[:function]
                    tool_calls[index][:name] = tc[:function][:name] if tc[:function][:name]
                    tool_calls[index][:arguments] << tc[:function][:arguments] if tc[:function][:arguments]
                  end
                end
              end

              finish_reason = choice[:finish_reason] if choice[:finish_reason]

              if parsed[:usage]
                usage = parsed[:usage]
                yield build_stream_event(:metadata,
                                         usage: Types::EventLoop::Usage.new(
                                           input_tokens: usage[:prompt_tokens] || 0,
                                           output_tokens: usage[:completion_tokens] || 0,
                                           total_tokens: usage[:total_tokens]
                                         ),
                                         metrics: Types::EventLoop::Metrics.new(latency_ms: 0))
              end
            end
          end

          yield build_stream_event(:content_block_stop) if current_data_type

          tool_calls.each_value do |tc|
            tool_use_start = Types::Streaming::ContentBlockStart.new(
              tool_use: Types::Streaming::ContentBlockStartToolUse.new(
                name: tc[:name],
                tool_use_id: tc[:id]
              )
            )
            yield build_stream_event(:content_block_start, start: tool_use_start)
            yield build_stream_event(:content_block_delta,
                                     delta: Types::Streaming::ContentBlockDelta.new(
                                       tool_use: Types::Streaming::ContentBlockDeltaToolUse.new(
                                         input: tc[:arguments]
                                       )
                                     ))
            yield build_stream_event(:content_block_stop)
          end

          stop_reason = map_finish_reason(finish_reason)
          yield build_stream_event(:message_stop, stop_reason: stop_reason)
        end
      end

      # Format the request body for the Mistral Chat Completions API.
      #
      # @param messages [Array<Hash>] conversation messages
      # @param system_prompt [String, nil] system prompt
      # @param tools [Array, nil] available tools
      # @param tool_choice [Object, nil] tool selection strategy
      # @return [Hash] the formatted request body
      def format_request(messages, system_prompt: nil, tools: nil, tool_choice: nil)
        formatted_messages = []

        if system_prompt
          formatted_messages << { role: "system", content: system_prompt }
        end

        messages.each do |msg|
          formatted_messages.concat(format_message(msg))
        end

        request = {
          model: @config[:model_id],
          messages: formatted_messages,
          stream: true
        }

        if tools && !tools.empty?
          request[:tools] = tools.map { |tool| format_tool_spec(tool) }
        end

        if tool_choice
          request[:tool_choice] = format_tool_choice(tool_choice)
        end

        request.merge!(@config[:params]) if @config[:params]

        request
      end

      private

      # Format a single message into OpenAI-compatible format.
      #
      # @param msg [Hash] a message with :role and :content keys
      # @return [Array<Hash>] one or more formatted messages
      def format_message(msg)
        role = msg[:role].to_s
        content = msg[:content]
        return [{ role: role, content: content }] if content.is_a?(String)

        formatted_content = []
        tool_calls_list = []
        tool_results = []

        Array(content).each do |block|
          next unless block.is_a?(Hash)

          if block[:text]
            formatted_content << { type: "text", text: block[:text] }
          elsif block[:tool_use]
            tu = block[:tool_use]
            tool_calls_list << {
              id: tu[:tool_use_id],
              type: "function",
              function: {
                name: tu[:name],
                arguments: tu[:input].is_a?(String) ? tu[:input] : JSON.generate(tu[:input] || {})
              }
            }
          elsif block[:tool_result]
            tr = block[:tool_result]
            result_content = Array(tr[:content]).map do |c|
              if c[:text] then c[:text]
              elsif c[:json] then JSON.generate(c[:json])
              else c.to_s
              end
            end.join("\n")
            tool_results << { role: "tool", tool_call_id: tr[:tool_use_id], content: result_content }
          end
        end

        result = []
        msg_hash = { role: role }
        msg_hash[:content] = formatted_content unless formatted_content.empty?
        msg_hash[:tool_calls] = tool_calls_list unless tool_calls_list.empty?
        result << msg_hash if msg_hash[:content] || msg_hash[:tool_calls]
        result.concat(tool_results)
        result.empty? ? [{ role: role, content: "" }] : result
      end

      # Format a ToolSpec into function calling format.
      #
      # @param tool [Strands::Types::Tools::ToolSpec, Hash] the tool specification
      # @return [Hash]
      def format_tool_spec(tool)
        if tool.is_a?(Types::Tools::ToolSpec)
          { type: "function", function: { name: tool.name, description: tool.description, parameters: tool.input_schema } }
        else
          { type: "function", function: { name: tool[:name], description: tool[:description], parameters: tool[:input_schema] } }
        end
      end

      # Format tool_choice into Mistral format.
      #
      # @param choice [Object] the tool choice configuration
      # @return [String, Hash]
      def format_tool_choice(choice)
        case choice
        when Types::Tools::ToolChoiceAuto then "auto"
        when Types::Tools::ToolChoiceAny then "any"
        when Types::Tools::ToolChoiceTool then { type: "function", function: { name: choice.name } }
        when Hash
          if choice[:auto] then "auto"
          elsif choice[:any] then "any"
          elsif choice[:tool] then { type: "function", function: { name: choice[:tool][:name] } }
          else "auto"
          end
        else "auto"
        end
      end

      # Map finish_reason to SDK stop_reason symbol.
      #
      # @param finish_reason [String, nil]
      # @return [Symbol]
      def map_finish_reason(finish_reason)
        case finish_reason
        when "tool_calls" then :tool_use
        when "length" then :max_tokens
        when "stop" then :end_turn
        else :end_turn
        end
      end

      # Handle non-success HTTP responses.
      #
      # @param response [Net::HTTPResponse]
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
          raise Strands::Error, "Mistral API error (400): #{error_message}"
        else
          if CONTEXT_OVERFLOW_MESSAGES.any? { |msg| error_message.downcase.include?(msg) }
            raise Types::Exceptions::ContextWindowOverflowError, error_message
          end
          raise Strands::Error, "Mistral API error (#{response.code}): #{error_message}"
        end
      end
    end
  end
end
