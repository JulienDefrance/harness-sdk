# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

module Strands
  module Models
    # Anthropic Claude model provider implementation.
    #
    # Implements the streaming interface using the Anthropic Messages API
    # with Server-Sent Events (SSE) for streaming responses.
    #
    # @example Basic usage
    #   model = Strands::Models::Anthropic.new(
    #     model_id: "claude-3-5-sonnet-20241022",
    #     max_tokens: 4096,
    #     api_key: ENV["ANTHROPIC_API_KEY"]
    #   )
    #   model.stream(messages) { |event| process(event) }
    #
    class Anthropic
      include Base
      include StreamEventBuilder

      # Default Anthropic API base URL
      DEFAULT_BASE_URL = "https://api.anthropic.com"

      # Anthropic API version
      API_VERSION = "2023-06-01"

      # Context overflow error messages
      OVERFLOW_MESSAGES = [
        "prompt is too long:",
        "input is too long",
        "input length exceeds context window",
        "input and output tokens exceed your context limit"
      ].freeze

      # @return [Hash] the model configuration
      attr_reader :config

      # Initialize the Anthropic model provider.
      #
      # @param model_id [String] the Claude model identifier
      # @param max_tokens [Integer] maximum tokens to generate
      # @param api_key [String, nil] Anthropic API key (defaults to ENV["ANTHROPIC_API_KEY"])
      # @param base_url [String] API base URL
      # @param params [Hash] additional model parameters (temperature, top_p, etc.)
      def initialize(model_id:, max_tokens: 4096, api_key: nil, base_url: DEFAULT_BASE_URL, **params)
        @config = {
          model_id: model_id,
          max_tokens: max_tokens,
          api_key: api_key || ENV.fetch("ANTHROPIC_API_KEY", nil),
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
      # Prevents API keys and secrets from leaking into logs, error reports,
      # or debugging output.
      #
      # @return [String]
      def inspect
        "#<#{self.class} model_id=#{@config[:model_id].inspect} base_url=#{@config[:base_url].inspect}>"
      end

      # Stream a conversation with the Anthropic model.
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
        request_body = format_request(messages, system_prompt: system_prompt, tools: tools, tool_choice: tool_choice)

        uri = URI.join(@config[:base_url], "/v1/messages")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = (uri.scheme == "https")
        http.read_timeout = 300

        request = Net::HTTP::Post.new(uri.path)
        request["Content-Type"] = "application/json"
        request["X-Api-Key"] = @config[:api_key]
        request["Anthropic-Version"] = API_VERSION
        request.body = JSON.generate(request_body)

        current_tool_use = nil
        tool_input_buffer = +""

        http.request(request) do |response|
          handle_error_response(response) unless response.is_a?(Net::HTTPSuccess)

          buffer = +""

          response.read_body do |chunk|
            buffer << chunk
            while (line_end = buffer.index("\n"))
              line = buffer.slice!(0, line_end + 1).strip
              next if line.empty?
              next unless line.start_with?("data: ")

              data = line[6..]
              next if data == "[DONE]"

              parsed = JSON.parse(data, symbolize_names: true)
              events = parse_anthropic_event(parsed, current_tool_use, tool_input_buffer)
              events.each do |event|
                yield event
              end

              # Track tool use state
              case parsed[:type]
              when "content_block_start"
                if parsed.dig(:content_block, :type) == "tool_use"
                  current_tool_use = parsed[:content_block]
                  tool_input_buffer.clear
                else
                  current_tool_use = nil
                end
              when "content_block_stop"
                current_tool_use = nil
                tool_input_buffer.clear
              when "content_block_delta"
                if parsed.dig(:delta, :type) == "input_json_delta"
                  tool_input_buffer << (parsed.dig(:delta, :partial_json) || "")
                end
              end
            end
          end
        end
      end

      # Format the request body for the Anthropic Messages API.
      #
      # @param messages [Array<Hash>] conversation messages
      # @param system_prompt [String, nil] system prompt
      # @param tools [Array, nil] available tools
      # @param tool_choice [Object, nil] tool selection strategy
      # @return [Hash] the formatted request body
      def format_request(messages, system_prompt: nil, tools: nil, tool_choice: nil)
        request = {
          model: @config[:model_id],
          max_tokens: @config[:max_tokens],
          messages: format_messages(messages),
          stream: true
        }

        request[:system] = system_prompt if system_prompt

        if tools && !tools.empty?
          request[:tools] = tools.map { |t| format_tool_spec(t) }
        end

        if tool_choice
          request[:tool_choice] = format_tool_choice(tool_choice)
        end

        # Merge additional params
        request.merge!(@config[:params]) if @config[:params] && !@config[:params].empty?

        request
      end

      private

      # Format messages for the Anthropic API.
      #
      # @param messages [Array<Hash>] raw messages
      # @return [Array<Hash>] formatted messages
      def format_messages(messages)
        messages.map do |msg|
          {
            role: msg[:role].to_s,
            content: format_content(msg[:content])
          }
        end
      end

      # Format content blocks for the Anthropic API.
      #
      # @param content [Array, String] content data
      # @return [Array<Hash>, String] formatted content
      def format_content(content)
        return content if content.is_a?(String)

        Array(content).map do |block|
          if block.is_a?(Hash)
            if block[:text]
              { type: "text", text: block[:text] }
            elsif block[:tool_use]
              tu = block[:tool_use]
              { type: "tool_use", id: tu[:tool_use_id], name: tu[:name], input: tu[:input] || {} }
            elsif block[:tool_result]
              tr = block[:tool_result]
              result_content = Array(tr[:content]).map do |c|
                if c[:text]
                  { type: "text", text: c[:text] }
                elsif c[:json]
                  { type: "text", text: JSON.generate(c[:json]) }
                elsif c[:image]
                  format_image_block(c[:image])
                else
                  { type: "text", text: c.to_s }
                end
              end
              { type: "tool_result", tool_use_id: tr[:tool_use_id], content: result_content }
            elsif block[:image]
              format_image_block(block[:image])
            else
              { type: "text", text: block.to_s }
            end
          else
            { type: "text", text: block.to_s }
          end
        end
      end

      # Format an image block for Anthropic.
      #
      # @param image [Hash] image data with :source and :format
      # @return [Hash] formatted image block
      def format_image_block(image)
        if image[:source] && image[:source][:bytes]
          data = [image[:source][:bytes]].pack("m0")
          media_type = "image/#{image[:format] || 'png'}"
          {
            type: "image",
            source: {
              type: "base64",
              media_type: media_type,
              data: data
            }
          }
        else
          { type: "text", text: "[image]" }
        end
      end

      # Format a tool spec for Anthropic.
      #
      # @param tool [Strands::Types::Tools::ToolSpec, Hash] tool specification
      # @return [Hash] Anthropic-formatted tool
      def format_tool_spec(tool)
        if tool.is_a?(Types::Tools::ToolSpec)
          {
            name: tool.name,
            description: tool.description,
            input_schema: tool.input_schema
          }
        else
          {
            name: tool[:name],
            description: tool[:description],
            input_schema: tool[:input_schema]
          }
        end
      end

      # Format tool choice for Anthropic.
      #
      # @param choice [Object] tool choice config
      # @return [Hash] Anthropic tool choice
      def format_tool_choice(choice)
        case choice
        when Types::Tools::ToolChoiceAuto
          { type: "auto" }
        when Types::Tools::ToolChoiceAny
          { type: "any" }
        when Types::Tools::ToolChoiceTool
          { type: "tool", name: choice.name }
        when Hash
          if choice[:auto]
            { type: "auto" }
          elsif choice[:any]
            { type: "any" }
          elsif choice[:tool]
            { type: "tool", name: choice[:tool][:name] }
          else
            { type: "auto" }
          end
        else
          { type: "auto" }
        end
      end

      # Parse an Anthropic SSE event into StreamEvent objects.
      #
      # @param event [Hash] parsed SSE data
      # @param current_tool_use [Hash, nil] current tool use context
      # @param tool_input_buffer [String] accumulated tool input
      # @return [Array<Strands::Types::Streaming::StreamEvent>] stream events
      def parse_anthropic_event(event, current_tool_use, tool_input_buffer)
        events = []

        case event[:type]
        when "message_start"
          events << build_stream_event(:message_start, role: :assistant)
          # Extract usage from message_start if present
          if event.dig(:message, :usage)
            usage_data = event[:message][:usage]
            events << build_stream_event(:metadata,
                                         usage: Types::EventLoop::Usage.new(
                                           input_tokens: usage_data[:input_tokens] || 0,
                                           output_tokens: usage_data[:output_tokens] || 0
                                         ),
                                         metrics: Types::EventLoop::Metrics.new(latency_ms: 0))
          end

        when "content_block_start"
          content_block = event[:content_block]
          if content_block[:type] == "tool_use"
            start = Types::Streaming::ContentBlockStart.new(
              tool_use: Types::Streaming::ContentBlockStartToolUse.new(
                name: content_block[:name],
                tool_use_id: content_block[:id]
              )
            )
            events << build_stream_event(:content_block_start, start: start)
          else
            events << build_stream_event(:content_block_start, start: Types::Streaming::ContentBlockStart.new)
          end

        when "content_block_delta"
          delta_data = event[:delta]
          case delta_data[:type]
          when "text_delta"
            events << build_stream_event(:content_block_delta,
                                         delta: Types::Streaming::ContentBlockDelta.new(text: delta_data[:text]))
          when "input_json_delta"
            events << build_stream_event(:content_block_delta,
                                         delta: Types::Streaming::ContentBlockDelta.new(
                                           tool_use: Types::Streaming::ContentBlockDeltaToolUse.new(
                                             input: delta_data[:partial_json] || ""
                                           )
                                         ))
          end

        when "content_block_stop"
          events << build_stream_event(:content_block_stop)

        when "message_delta"
          # message_delta contains stop_reason and usage
          if event.dig(:delta, :stop_reason)
            stop_reason = map_stop_reason(event[:delta][:stop_reason])
            events << build_stream_event(:message_stop, stop_reason: stop_reason)
          end
          if event[:usage]
            events << build_stream_event(:metadata,
                                         usage: Types::EventLoop::Usage.new(
                                           input_tokens: 0,
                                           output_tokens: event[:usage][:output_tokens] || 0
                                         ),
                                         metrics: Types::EventLoop::Metrics.new(latency_ms: 0))
          end

        when "message_stop"
          # Final message_stop event (stop_reason already handled by message_delta)
          nil

        when "error"
          error_msg = event.dig(:error, :message) || "Unknown error"
          if OVERFLOW_MESSAGES.any? { |msg| error_msg.downcase.include?(msg) }
            raise Types::Exceptions::ContextWindowOverflowError, error_msg
          end
          raise Strands::Error, "Anthropic stream error: #{error_msg}"
        end

        events
      end

      # Map Anthropic stop_reason to SDK stop reason symbol.
      #
      # @param reason [String] Anthropic stop reason
      # @return [Symbol] SDK stop reason
      def map_stop_reason(reason)
        case reason
        when "end_turn"
          :end_turn
        when "tool_use"
          :tool_use
        when "max_tokens"
          :max_tokens
        when "stop_sequence"
          :stop_sequence
        else
          :end_turn
        end
      end

      # Handle non-success HTTP responses from Anthropic.
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
          if OVERFLOW_MESSAGES.any? { |msg| error_message.downcase.include?(msg) }
            raise Types::Exceptions::ContextWindowOverflowError, error_message
          end
          raise Strands::Error, "Anthropic API error (400): #{error_message}"
        when 529
          # Anthropic overloaded
          raise Types::Exceptions::ModelThrottledError, error_message
        else
          if OVERFLOW_MESSAGES.any? { |msg| error_message.downcase.include?(msg) }
            raise Types::Exceptions::ContextWindowOverflowError, error_message
          end
          raise Strands::Error, "Anthropic API error (#{response.code}): #{error_message}"
        end
      end

    end
  end
end
