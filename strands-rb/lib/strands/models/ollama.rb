# frozen_string_literal: true

require "net/http"
require "uri"
require "json"
require "securerandom"

module Strands
  module Models
    # Ollama model provider implementation.
    #
    # Implements the streaming interface using the Ollama chat API
    # for local model inference. No extra gems required.
    #
    # @example Basic usage
    #   model = Strands::Models::Ollama.new(
    #     model_id: "llama3",
    #     host: "http://localhost:11434"
    #   )
    #   model.stream(messages) { |event| process(event) }
    #
    class Ollama
      include Base
      include StreamEventBuilder

      # Default Ollama host
      DEFAULT_HOST = "http://localhost:11434"

      # Context overflow error messages from Ollama
      OVERFLOW_MESSAGES = [
        "the prompt is longer than the context length",
        "the input length exceeds the context length",
        "exceeds the available context",
        "exceeded max context length"
      ].freeze

      # @return [Hash] the model configuration
      attr_reader :config

      # Initialize the Ollama model provider.
      #
      # @param model_id [String] the Ollama model name (e.g., "llama3", "mistral")
      # @param host [String] Ollama server address
      # @param params [Hash] additional parameters (temperature, top_p, num_predict, etc.)
      def initialize(model_id:, host: DEFAULT_HOST, **params)
        @config = {
          model_id: model_id,
          host: host,
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
      # Prevents credentials from leaking into logs, error reports,
      # or debugging output.
      #
      # @return [String]
      def inspect
        "#<#{self.class} model_id=#{@config[:model_id].inspect} host=#{@config[:host].inspect}>"
      end

      # Stream a conversation with the Ollama model.
      #
      # @param messages [Array<Hash>] conversation messages
      # @param system_prompt [String, nil] system prompt
      # @param tools [Array<Strands::Types::Tools::ToolSpec>, nil] available tools
      # @param tool_choice [Object, nil] tool selection strategy (not used by Ollama)
      # @param kwargs [Hash] additional parameters
      # @yieldparam event [Strands::Types::Streaming::StreamEvent] a stream event
      # @return [void]
      # @raise [Strands::Types::Exceptions::ContextWindowOverflowError] if input exceeds context
      # @raise [Strands::Types::Exceptions::ModelThrottledError] if server is overloaded
      def stream(messages, system_prompt: nil, tools: nil, tool_choice: nil, **kwargs)
        request_body = format_request(messages, system_prompt: system_prompt, tools: tools)

        uri = URI.join(@config[:host], "/api/chat")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = (uri.scheme == "https")
        http.read_timeout = 600 # Ollama can be slow for large models

        request = Net::HTTP::Post.new(uri.path)
        request["Content-Type"] = "application/json"
        request.body = JSON.generate(request_body)

        tool_calls = []
        has_content = false

        http.request(request) do |response|
          handle_error_response(response) unless response.is_a?(Net::HTTPSuccess)

          # Emit message start
          yield build_stream_event(:message_start, role: :assistant)

          content_started = false
          buffer = +""

          response.read_body do |chunk|
            buffer << chunk
            while (line_end = buffer.index("\n"))
              line = buffer.slice!(0, line_end + 1).strip
              next if line.empty?

              parsed = JSON.parse(line, symbolize_names: true)

              message = parsed[:message]
              next unless message

              # Handle text content
              if message[:content] && !message[:content].empty?
                unless content_started
                  yield build_stream_event(:content_block_start, start: Types::Streaming::ContentBlockStart.new)
                  content_started = true
                end
                has_content = true
                yield build_stream_event(:content_block_delta,
                                         delta: Types::Streaming::ContentBlockDelta.new(text: message[:content]))
              end

              # Handle tool calls
              if message[:tool_calls]
                message[:tool_calls].each do |tc|
                  tool_calls << tc
                end
              end

              # Handle done signal
              if parsed[:done]
                # Close content block if open
                if content_started
                  yield build_stream_event(:content_block_stop)
                  content_started = false
                end

                # Emit tool use blocks
                tool_calls.each do |tc|
                  func = tc[:function]
                  tool_use_id = SecureRandom.uuid
                  tool_use_start = Types::Streaming::ContentBlockStart.new(
                    tool_use: Types::Streaming::ContentBlockStartToolUse.new(
                      name: func[:name],
                      tool_use_id: tool_use_id
                    )
                  )
                  yield build_stream_event(:content_block_start, start: tool_use_start)

                  input = func[:arguments].is_a?(String) ? func[:arguments] : JSON.generate(func[:arguments] || {})
                  yield build_stream_event(:content_block_delta,
                                           delta: Types::Streaming::ContentBlockDelta.new(
                                             tool_use: Types::Streaming::ContentBlockDeltaToolUse.new(
                                               input: input
                                             )
                                           ))

                  yield build_stream_event(:content_block_stop)
                end

                # Determine stop reason
                stop_reason = if !tool_calls.empty?
                                :tool_use
                              else
                                :end_turn
                              end

                yield build_stream_event(:message_stop, stop_reason: stop_reason)

                # Emit metadata if available
                if parsed[:eval_count] || parsed[:prompt_eval_count]
                  yield build_stream_event(:metadata,
                                           usage: Types::EventLoop::Usage.new(
                                             input_tokens: parsed[:prompt_eval_count] || 0,
                                             output_tokens: parsed[:eval_count] || 0
                                           ),
                                           metrics: Types::EventLoop::Metrics.new(
                                             latency_ms: parsed[:total_duration] ? (parsed[:total_duration] / 1_000_000) : 0
                                           ))
                end
              end
            end
          end
        end
      end

      # Format the request body for the Ollama chat API.
      #
      # @param messages [Array<Hash>] conversation messages
      # @param system_prompt [String, nil] system prompt
      # @param tools [Array, nil] available tools
      # @return [Hash] the formatted request body
      def format_request(messages, system_prompt: nil, tools: nil)
        formatted_messages = []

        # Add system message
        if system_prompt
          formatted_messages << { role: "system", content: system_prompt }
        end

        # Format conversation messages
        messages.each do |msg|
          formatted_messages << format_message(msg)
        end

        request = {
          model: @config[:model_id],
          messages: formatted_messages,
          stream: true
        }

        # Add tools if provided
        if tools && !tools.empty?
          request[:tools] = tools.map { |t| format_tool_spec(t) }
        end

        # Add options from params
        options = {}
        params = @config[:params] || {}
        options[:temperature] = params[:temperature] if params[:temperature]
        options[:top_p] = params[:top_p] if params[:top_p]
        options[:num_predict] = params[:max_tokens] || params[:num_predict] if params[:max_tokens] || params[:num_predict]
        options[:stop] = params[:stop_sequences] if params[:stop_sequences]

        request[:options] = options unless options.empty?
        request[:keep_alive] = params[:keep_alive] if params[:keep_alive]

        request
      end

      private

      # Format a single message for Ollama.
      #
      # @param msg [Hash] message with :role and :content
      # @return [Hash] formatted message
      def format_message(msg)
        role = msg[:role].to_s
        content = msg[:content]

        if content.is_a?(String)
          return { role: role, content: content }
        end

        # Process content blocks - Ollama uses simple text content
        text_parts = []
        images = []
        tool_calls_list = []

        Array(content).each do |block|
          next unless block.is_a?(Hash)

          if block[:text]
            text_parts << block[:text]
          elsif block[:tool_use]
            tu = block[:tool_use]
            tool_calls_list << {
              function: {
                name: tu[:name],
                arguments: tu[:input] || {}
              }
            }
          elsif block[:tool_result]
            tr = block[:tool_result]
            result_text = Array(tr[:content]).map do |c|
              if c[:text]
                c[:text]
              elsif c[:json]
                JSON.generate(c[:json])
              else
                c.to_s
              end
            end.join("\n")
            text_parts << result_text
          elsif block[:image]
            if block[:image][:source] && block[:image][:source][:bytes]
              images << [block[:image][:source][:bytes]].pack("m0")
            end
          end
        end

        result = { role: role, content: text_parts.join("\n") }
        result[:images] = images unless images.empty?
        result[:tool_calls] = tool_calls_list unless tool_calls_list.empty?
        result
      end

      # Format a tool spec for Ollama.
      #
      # @param tool [Strands::Types::Tools::ToolSpec, Hash] tool specification
      # @return [Hash] Ollama-compatible tool definition
      def format_tool_spec(tool)
        if tool.is_a?(Types::Tools::ToolSpec)
          {
            type: "function",
            function: {
              name: tool.name,
              description: tool.description,
              parameters: tool.input_schema
            }
          }
        else
          {
            type: "function",
            function: {
              name: tool[:name],
              description: tool[:description],
              parameters: tool[:input_schema]
            }
          }
        end
      end

      # Handle non-success HTTP responses from Ollama.
      #
      # @param response [Net::HTTPResponse] the error response
      # @raise [Strands::Types::Exceptions::ContextWindowOverflowError]
      # @raise [Strands::Types::Exceptions::ModelThrottledError]
      # @raise [Strands::Error]
      def handle_error_response(response)
        body = begin
          JSON.parse(response.body, symbolize_names: true)
        rescue StandardError
          { error: response.body }
        end

        error_message = body[:error] || response.body.to_s
        error_message = error_message.to_s

        if OVERFLOW_MESSAGES.any? { |msg| error_message.downcase.include?(msg) }
          raise Types::Exceptions::ContextWindowOverflowError, error_message
        end

        case response.code.to_i
        when 429, 503
          raise Types::Exceptions::ModelThrottledError, error_message
        else
          raise Strands::Error, "Ollama API error (#{response.code}): #{error_message}"
        end
      end

    end
  end
end
