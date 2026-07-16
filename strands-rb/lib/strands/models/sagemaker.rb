# frozen_string_literal: true

require "json"
require "securerandom"

module Strands
  module Models
    # AWS SageMaker model provider implementation.
    #
    # Uses the SageMaker Runtime API to invoke an endpoint with response
    # streaming. The aws-sdk-sagemakerruntime gem is lazily loaded on first use.
    #
    # @example Basic usage
    #   model = Strands::Models::SageMaker.new(
    #     endpoint_name: "my-llm-endpoint",
    #     region_name: "us-west-2"
    #   )
    #   model.stream(messages) { |event| process(event) }
    #
    class SageMaker
      include Base
      include StreamEventBuilder

      # @return [Hash] the model configuration
      attr_reader :config

      # Initialize the SageMaker model provider.
      #
      # @param endpoint_name [String] the SageMaker endpoint name
      # @param region_name [String, nil] AWS region (uses SDK default if nil)
      # @param model_id [String, nil] optional model identifier for multi-model endpoints
      # @param params [Hash] additional parameters (max_tokens, temperature, etc.)
      def initialize(endpoint_name:, region_name: nil, model_id: nil, **params)
        @config = {
          endpoint_name: endpoint_name,
          region_name: region_name,
          model_id: model_id,
          params: params
        }
        @client = nil
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
        "#<#{self.class} endpoint_name=#{@config[:endpoint_name].inspect} model_id=#{@config[:model_id].inspect}>"
      end

      # Stream a conversation with a SageMaker endpoint.
      #
      # @param messages [Array<Hash>] conversation messages
      # @param system_prompt [String, nil] system prompt
      # @param tools [Array<Strands::Types::Tools::ToolSpec>, nil] available tools
      # @param tool_choice [Object, nil] tool selection strategy
      # @param kwargs [Hash] additional parameters
      # @yieldparam event [Strands::Types::Streaming::StreamEvent] a stream event
      # @return [void]
      # @raise [Strands::Error] on invocation errors
      def stream(messages, system_prompt: nil, tools: nil, tool_choice: nil, **kwargs)
        request_body = format_request(messages, system_prompt: system_prompt, tools: tools, tool_choice: tool_choice)

        tool_calls = {}
        current_data_type = nil
        finish_reason = nil
        message_started = false

        event_handler = proc do |event_stream|
          event_stream.on_payload_part_event do |event|
            bytes = event.bytes
            next unless bytes

            payload = bytes.force_encoding("UTF-8")
            # Parse SSE lines from the payload
            payload.each_line do |line|
              line = line.strip
              next if line.empty?
              next unless line.start_with?("data: ")

              data = line[6..]
              next if data == "[DONE]"

              parsed = begin
                JSON.parse(data, symbolize_names: true)
              rescue JSON::ParserError
                next
              end

              unless message_started
                yield build_stream_event(:message_start, role: :assistant)
                message_started = true
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
        end

        invoke_params = {
          endpoint_name: @config[:endpoint_name],
          body: JSON.generate(request_body),
          content_type: "application/json",
          accept: "application/jsonlines"
        }

        client.invoke_endpoint_with_response_stream(**invoke_params, &event_handler)

        unless message_started
          yield build_stream_event(:message_start, role: :assistant)
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

      # Format the request body for the SageMaker endpoint.
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
          messages: formatted_messages,
          stream: true
        }

        request[:model] = @config[:model_id] if @config[:model_id]

        if tools && !tools.empty?
          request[:tools] = tools.map { |tool| format_tool_spec(tool) }
        end

        params = @config[:params] || {}
        request[:max_tokens] = params[:max_tokens] if params[:max_tokens]
        request[:temperature] = params[:temperature] if params[:temperature]
        request[:top_p] = params[:top_p] if params[:top_p]

        request
      end

      private

      # Lazily creates the SageMaker Runtime client.
      #
      # @return [Aws::SageMakerRuntime::Client]
      # @raise [Strands::Error] if the aws-sdk-sagemakerruntime gem is not available
      def client
        @client ||= begin
          require "aws-sdk-sagemakerruntime"
          options = {}
          options[:region] = @config[:region_name] if @config[:region_name]
          Aws::SageMakerRuntime::Client.new(**options)
        rescue LoadError
          raise Strands::Error,
                "aws-sdk-sagemakerruntime gem is required for SageMaker. " \
                "Add gem 'aws-sdk-sagemakerruntime' to your Gemfile."
        end
      end

      # Format a single message into OpenAI-compatible format.
      #
      # @param msg [Hash] a message with :role and :content keys
      # @return [Array<Hash>]
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

      # Format a ToolSpec.
      #
      # @param tool [Strands::Types::Tools::ToolSpec, Hash]
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
    end
  end
end
