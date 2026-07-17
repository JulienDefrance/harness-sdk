# frozen_string_literal: true

require "net/http"
require "uri"
require "json"
require "securerandom"

module Strands
  module Models
    # llama.cpp server model provider implementation.
    #
    # Connects to a llama.cpp server exposing an OpenAI-compatible
    # /v1/chat/completions endpoint. Supports grammar constraints and
    # llama.cpp-specific sampling parameters.
    #
    # @example Basic usage
    #   model = Strands::Models::LlamaCpp.new(
    #     model_id: "default",
    #     base_url: "http://localhost:8080"
    #   )
    #   model.stream(messages) { |event| process(event) }
    #
    class LlamaCpp
      include Base
      include StreamEventBuilder

      # Default llama.cpp server URL
      DEFAULT_BASE_URL = "http://localhost:8080"

      # @return [Hash] the model configuration
      attr_reader :config

      # Initialize the llama.cpp model provider.
      #
      # @param model_id [String] the model identifier (default: "default")
      # @param base_url [String] URL of the llama.cpp server
      # @param params [Hash] additional parameters (grammar, repeat_penalty, top_k, etc.)
      def initialize(model_id: "default", base_url: DEFAULT_BASE_URL, **params)
        @config = {
          model_id: model_id,
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

      # Returns a string representation.
      #
      # @return [String]
      def inspect
        "#<#{self.class} model_id=#{@config[:model_id].inspect} base_url=#{@config[:base_url].inspect}>"
      end

      # Stream a conversation with the llama.cpp server.
      #
      # @param messages [Array<Hash>] conversation messages
      # @param system_prompt [String, nil] system prompt
      # @param tools [Array<Strands::Types::Tools::ToolSpec>, nil] available tools
      # @param tool_choice [Object, nil] tool selection strategy
      # @param kwargs [Hash] additional parameters
      # @yieldparam event [Strands::Types::Streaming::StreamEvent] a stream event
      # @return [void]
      # @raise [Strands::Error] on HTTP errors
      def stream(messages, system_prompt: nil, tools: nil, tool_choice: nil, **kwargs)
        request_body = format_request(messages, system_prompt: system_prompt, tools: tools, tool_choice: tool_choice)

        uri = URI.join(@config[:base_url], "/v1/chat/completions")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = (uri.scheme == "https")
        http.read_timeout = 600

        request = Net::HTTP::Post.new(uri.path)
        request["Content-Type"] = "application/json"
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

      # Format the request body for the llama.cpp server.
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

        # Add llama.cpp-specific params
        params = @config[:params] || {}
        request[:grammar] = params[:grammar] if params[:grammar]
        request[:json_schema] = params[:json_schema] if params[:json_schema]
        request[:temperature] = params[:temperature] if params[:temperature]
        request[:top_p] = params[:top_p] if params[:top_p]
        request[:max_tokens] = params[:max_tokens] if params[:max_tokens]
        request[:repeat_penalty] = params[:repeat_penalty] if params[:repeat_penalty]
        request[:top_k] = params[:top_k] if params[:top_k]
        request[:min_p] = params[:min_p] if params[:min_p]
        request[:typical_p] = params[:typical_p] if params[:typical_p]
        request[:tfs_z] = params[:tfs_z] if params[:tfs_z]
        request[:mirostat] = params[:mirostat] if params[:mirostat]
        request[:mirostat_lr] = params[:mirostat_lr] if params[:mirostat_lr]
        request[:mirostat_ent] = params[:mirostat_ent] if params[:mirostat_ent]

        request
      end

      private

      # Format a single message into OpenAI format.
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
        else
          raise Strands::Error, "LlamaCpp API error (#{response.code}): #{error_message}"
        end
      end
    end
  end
end
