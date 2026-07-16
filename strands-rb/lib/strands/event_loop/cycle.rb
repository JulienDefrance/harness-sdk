# frozen_string_literal: true

module Strands
  module EventLoop
    # Implements the core agent turn cycle.
    #
    # The Cycle orchestrates:
    # 1. Sending messages to the model via stream()
    # 2. Collecting the streaming response into content blocks
    # 3. Detecting tool_use blocks in the response
    # 4. Executing tools and appending results
    # 5. Looping until stop_reason is end_turn (or max turns reached)
    # 6. Firing hook events at each lifecycle point
    # 7. Respecting intervention decisions (Deny stops, Guide prepends feedback)
    # 8. Handling errors with retry logic (exponential backoff)
    #
    # @example Basic usage
    #   cycle = Strands::EventLoop::Cycle.new(
    #     agent: agent,
    #     retry_strategy: Strands::EventLoop::RetryStrategy.new
    #   )
    #   result = cycle.run(invocation_state: {})
    #
    class Cycle
      # @return [Object] the agent instance
      attr_reader :agent

      # @return [RetryStrategy] the retry strategy for error handling
      attr_reader :retry_strategy

      # @return [Integer] maximum number of turns (tool loops) before stopping
      attr_reader :max_turns

      # Default maximum turns to prevent infinite loops
      DEFAULT_MAX_TURNS = 50

      # Creates a new Cycle.
      #
      # @param agent [Object] the agent to run the cycle for
      # @param retry_strategy [RetryStrategy] retry configuration
      # @param max_turns [Integer] maximum turns before force-stopping
      def initialize(agent:, retry_strategy: nil, max_turns: DEFAULT_MAX_TURNS)
        @agent = agent
        @retry_strategy = retry_strategy || RetryStrategy.new
        @max_turns = max_turns
        @turn_count = 0
      end

      # Run the event loop cycle until completion.
      #
      # @param invocation_state [Hash] state carried through the invocation
      # @return [Hash] result with :stop_reason, :message, :metrics
      def run(invocation_state: {})
        @turn_count = 0

        loop do
          @turn_count += 1

          if @turn_count > @max_turns
            return build_result(stop_reason: :limit_turns, message: last_assistant_message)
          end

          # Fire BeforeModelCallEvent and check for intervention cancellation
          before_model_event = Hooks::BeforeModelCallEvent.new(
            agent: agent,
            invocation_state: invocation_state
          )
          fire_hook(before_model_event)

          if before_model_event.cancel
            # Model call was denied by intervention
            cancel_message = build_cancel_message(before_model_event.cancel)
            append_message(cancel_message)
            return build_result(stop_reason: :end_turn, message: cancel_message)
          end

          # Call the model with retry logic
          stop_reason, message = call_model_with_retry(invocation_state)

          # Fire AfterModelCallEvent
          after_model_event = Hooks::AfterModelCallEvent.new(
            agent: agent,
            invocation_state: invocation_state,
            stop_reason: stop_reason.to_s,
            message: message
          )
          fire_hook(after_model_event)

          # If hook requested retry, loop again without processing tools
          next if after_model_event.retry

          # Append assistant message
          append_message(message)

          # Check stop reason
          case stop_reason
          when :end_turn, :max_tokens, :stop_sequence
            return build_result(stop_reason: stop_reason, message: message)
          when :tool_use
            # Process tool calls
            process_tool_calls(message, invocation_state)
          else
            # Unknown stop reason - treat as end
            return build_result(stop_reason: stop_reason, message: message)
          end
        end
      end

      private

      # Call the model with retry logic for transient errors.
      #
      # @param invocation_state [Hash] invocation state
      # @return [Array(Symbol, Hash)] tuple of [stop_reason, message]
      def call_model_with_retry(invocation_state)
        attempt = 0

        loop do
          begin
            return stream_and_collect(invocation_state)
          rescue StandardError => e
            # Fire AfterModelCallEvent with exception for retry hooks
            after_model_event = Hooks::AfterModelCallEvent.new(
              agent: agent,
              invocation_state: invocation_state,
              exception: e
            )
            fire_hook(after_model_event)

            # Retry if strategy allows or hook requests it
            if retry_strategy.should_retry?(attempt) || after_model_event.retry
              delay = retry_strategy.delay_for(attempt)
              sleep(delay)
              attempt += 1
              next
            end

            # Re-raise if no more retries
            raise Types::Exceptions::EventLoopError.new(e, request_state: invocation_state)
          end
        end
      end

      # Stream messages from the model and collect the response.
      #
      # @param invocation_state [Hash] invocation state
      # @return [Array(Symbol, Hash)] tuple of [stop_reason, message_hash]
      def stream_and_collect(invocation_state)
        content_blocks = []
        current_text = +""
        current_tool_use = nil
        current_tool_input = +""
        stop_reason = :end_turn

        model = agent.model
        messages = agent.messages
        system_prompt = agent.system_prompt
        tool_specs = agent.tool_registry.tool_specs

        model.stream(messages, system_prompt: system_prompt, tools: tool_specs) do |event|
          # Notify callback handler of raw streaming events
          notify_callback(event)

          case event.event_type
          when :message_start
            # Message started - nothing to collect yet
          when :content_block_start
            start_info = event.content_block_start&.start
            if start_info&.tool_use
              # Starting a tool use block
              current_tool_use = start_info.tool_use
              current_tool_input = +""
            end
          when :content_block_delta
            delta = event.content_block_delta&.delta
            if delta
              if delta.text
                current_text << delta.text
              elsif delta.tool_use
                current_tool_input << (delta.tool_use.input || "")
              end
            end
          when :content_block_stop
            if current_tool_use
              # Finalize tool use block
              parsed_input = parse_tool_input(current_tool_input)
              content_blocks << {
                tool_use: Types::Tools::ToolUse.new(
                  name: current_tool_use.name,
                  tool_use_id: current_tool_use.tool_use_id,
                  input: parsed_input
                )
              }
              current_tool_use = nil
              current_tool_input = +""
            elsif !current_text.empty?
              # Finalize text block
              content_blocks << { text: current_text.dup }
              current_text = +""
            end
          when :message_stop
            stop_reason = event.message_stop&.stop_reason || :end_turn
          when :metadata
            # Usage/metrics info - could be captured for telemetry
          end
        end

        # Handle any trailing text that wasn't terminated by content_block_stop
        unless current_text.empty?
          content_blocks << { text: current_text.dup }
        end

        message = { role: :assistant, content: content_blocks }
        [stop_reason, message]
      end

      # Process tool calls from the assistant message.
      #
      # @param message [Hash] the assistant message containing tool_use blocks
      # @param invocation_state [Hash] invocation state
      def process_tool_calls(message, invocation_state)
        tool_uses = extract_tool_uses(message)
        tool_results = []

        tool_uses.each do |tool_use|
          # Fire BeforeToolCallEvent
          before_tool_event = Hooks::BeforeToolCallEvent.new(
            agent: agent,
            selected_tool: agent.tool_registry.get(tool_use.name),
            tool_use: tool_use,
            invocation_state: invocation_state
          )
          fire_hook(before_tool_event)

          # Check if tool was cancelled by intervention
          if before_tool_event.cancel_tool
            cancel_content = [Types::Tools::ToolResultContent.new(
              text: before_tool_event.cancel_tool.to_s
            )]
            result = Types::Tools::ToolResult.new(
              tool_use_id: tool_use.tool_use_id,
              content: cancel_content,
              status: :error
            )
          else
            # Execute the tool
            executor = Tools::Executor.new(agent.tool_registry)
            result = executor.execute(tool_use, agent: agent, invocation_state: invocation_state)
          end

          # Fire AfterToolCallEvent
          after_tool_event = Hooks::AfterToolCallEvent.new(
            agent: agent,
            selected_tool: agent.tool_registry.get(tool_use.name),
            tool_use: tool_use,
            invocation_state: invocation_state,
            result: result
          )
          fire_hook(after_tool_event)

          # Use potentially transformed result
          tool_results << (after_tool_event.result || result)
        end

        # Append tool results as a user message
        tool_result_message = {
          role: :user,
          content: tool_results.map { |r| { tool_result: r } }
        }
        append_message(tool_result_message)
      end

      # Extract ToolUse objects from a message's content blocks.
      #
      # @param message [Hash] a message hash
      # @return [Array<Types::Tools::ToolUse>]
      def extract_tool_uses(message)
        content = message[:content] || []
        content.filter_map { |block| block[:tool_use] }
      end

      # Parse tool input JSON string into a Hash.
      #
      # @param input_str [String] JSON string of tool input
      # @return [Hash]
      def parse_tool_input(input_str)
        return {} if input_str.nil? || input_str.empty?

        require "json"
        JSON.parse(input_str, symbolize_names: true)
      rescue JSON::ParserError
        { raw: input_str }
      end

      # Notify the callback handler of a stream event.
      #
      # @param event [Types::Streaming::StreamEvent] the streaming event
      def notify_callback(event)
        handler = agent.callback_handler
        return unless handler

        case event.event_type
        when :content_block_delta
          delta = event.content_block_delta&.delta
          if delta&.text
            handler.call(data: delta.text, complete: false)
          end
        when :message_stop
          handler.call(data: "", complete: true)
        when :content_block_start
          start_info = event.content_block_start&.start
          if start_info&.tool_use
            handler.call(event: event, tool_use: start_info.tool_use)
          end
        end
      end

      # Build a cancellation message from intervention feedback.
      #
      # @param cancel_text [String, true] the cancellation text
      # @return [Hash] an assistant message
      def build_cancel_message(cancel_text)
        text = cancel_text.is_a?(String) ? cancel_text : "Operation denied by intervention"
        { role: :assistant, content: [{ text: text }] }
      end

      # Append a message to the agent's conversation history.
      #
      # @param message [Hash] the message to append
      def append_message(message)
        agent.messages << message

        # Fire MessageAddedEvent
        event = Hooks::MessageAddedEvent.new(agent: agent, message: message)
        fire_hook(event)
      end

      # Fire a hook event through the agent's hook registry.
      #
      # @param event [Hooks::Event] the event to fire
      def fire_hook(event)
        agent.hook_registry.fire(event)
      end

      # Get the last assistant message from the conversation.
      #
      # @return [Hash, nil]
      def last_assistant_message
        agent.messages.reverse_each.find { |m| m[:role] == :assistant }
      end

      # Build the result hash.
      #
      # @param stop_reason [Symbol] why the cycle stopped
      # @param message [Hash, nil] the final message
      # @return [Hash]
      def build_result(stop_reason:, message:)
        { stop_reason: stop_reason, message: message, metrics: {} }
      end
    end
  end
end
