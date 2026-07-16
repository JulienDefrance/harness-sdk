# frozen_string_literal: true

module Strands
  module Hooks
    # Base class for all hook events.
    # Events are immutable data containers that carry context about
    # what happened in the agent lifecycle.
    class Event
      # @return [Boolean] whether callbacks should be invoked in reverse order
      def reverse_callbacks?
        false
      end
    end

    # Base class for events associated with a specific agent instance.
    class AgentEvent < Event
      # @return [Object] the agent that triggered this event
      attr_reader :agent

      # @param agent [Object] the agent instance
      def initialize(agent:)
        @agent = agent
      end
    end

    # Fired after the agent has been fully initialized.
    # Hook providers can use this for setup tasks requiring a ready agent.
    class AgentInitializedEvent < AgentEvent
    end

    # Fired before the agent begins processing a new request.
    # Allows request-level setup, logging, or validation.
    #
    # @attr_reader invocation_state [Hash] state passed through the invocation
    # @attr_reader messages [Array, nil] input messages (modifiable by hooks)
    class BeforeInvocationEvent < AgentEvent
      attr_reader :invocation_state
      attr_accessor :messages, :cancel

      # @param agent [Object] the agent instance
      # @param invocation_state [Hash] invocation state/context
      # @param messages [Array, nil] input messages
      def initialize(agent:, invocation_state: {}, messages: nil)
        super(agent: agent)
        @invocation_state = invocation_state
        @messages = messages
        @cancel = false
      end
    end

    # Fired after the agent has completed processing a request.
    # Uses reverse callback ordering for cleanup semantics.
    #
    # @attr_reader invocation_state [Hash] state passed through the invocation
    # @attr_reader result [Object, nil] the result of the invocation
    class AfterInvocationEvent < AgentEvent
      attr_reader :invocation_state, :result
      attr_accessor :resume

      # @param agent [Object] the agent instance
      # @param invocation_state [Hash] invocation state/context
      # @param result [Object, nil] the invocation result
      def initialize(agent:, invocation_state: {}, result: nil)
        super(agent: agent)
        @invocation_state = invocation_state
        @result = result
        @resume = nil
      end

      def reverse_callbacks?
        true
      end
    end

    # Fired when a message is added to the agent's conversation history.
    #
    # @attr_reader message [Hash] the message that was added
    class MessageAddedEvent < AgentEvent
      attr_reader :message

      # @param agent [Object] the agent instance
      # @param message [Hash] the message added to history
      def initialize(agent:, message:)
        super(agent: agent)
        @message = message
      end
    end

    # Fired before a tool is invoked.
    #
    # @attr_reader selected_tool [Object, nil] the tool to be invoked
    # @attr_reader tool_use [Hash] the tool parameters
    # @attr_reader invocation_state [Hash] keyword arguments passed to the tool
    class BeforeToolCallEvent < AgentEvent
      attr_accessor :selected_tool, :tool_use, :cancel_tool

      attr_reader :invocation_state

      # @param agent [Object] the agent instance
      # @param selected_tool [Object, nil] the tool to invoke
      # @param tool_use [Hash] tool parameters
      # @param invocation_state [Hash] state passed through the invocation
      def initialize(agent:, selected_tool:, tool_use:, invocation_state: {})
        super(agent: agent)
        @selected_tool = selected_tool
        @tool_use = tool_use
        @invocation_state = invocation_state
        @cancel_tool = false
      end
    end

    # Fired after a tool invocation completes.
    # Uses reverse callback ordering for cleanup semantics.
    #
    # @attr_reader selected_tool [Object, nil] the tool that was invoked
    # @attr_reader tool_use [Hash] the tool parameters used
    # @attr_reader invocation_state [Hash] keyword arguments passed to the tool
    class AfterToolCallEvent < AgentEvent
      attr_reader :selected_tool, :tool_use, :invocation_state
      attr_accessor :result, :retry

      # @param agent [Object] the agent instance
      # @param selected_tool [Object, nil] the tool that was invoked
      # @param tool_use [Hash] tool parameters used
      # @param invocation_state [Hash] state passed through the invocation
      # @param result [Object] the tool execution result
      # @param exception [Exception, nil] exception if tool failed
      def initialize(agent:, selected_tool:, tool_use:, invocation_state: {}, result: nil, exception: nil)
        super(agent: agent)
        @selected_tool = selected_tool
        @tool_use = tool_use
        @invocation_state = invocation_state
        @result = result
        @exception = exception
        @retry = false
      end

      # @return [Exception, nil] exception if the tool execution failed
      attr_reader :exception

      def reverse_callbacks?
        true
      end
    end

    # Fired before the model is invoked for inference.
    #
    # @attr_reader invocation_state [Hash] state passed through the invocation
    class BeforeModelCallEvent < AgentEvent
      attr_reader :invocation_state
      attr_accessor :cancel

      # @param agent [Object] the agent instance
      # @param invocation_state [Hash] state passed through the invocation
      def initialize(agent:, invocation_state: {})
        super(agent: agent)
        @invocation_state = invocation_state
        @cancel = false
      end
    end

    # Fired after the model invocation completes.
    # Uses reverse callback ordering for cleanup semantics.
    #
    # @attr_reader invocation_state [Hash] state passed through the invocation
    # @attr_reader stop_reason [String, nil] why the model stopped
    # @attr_reader message [Hash, nil] the generated message
    # @attr_reader exception [Exception, nil] exception if model failed
    class AfterModelCallEvent < AgentEvent
      attr_reader :invocation_state, :stop_reason, :message, :exception
      attr_accessor :retry

      # @param agent [Object] the agent instance
      # @param invocation_state [Hash] state passed through the invocation
      # @param stop_reason [String, nil] why the model stopped generating
      # @param message [Hash, nil] the generated message from the model
      # @param exception [Exception, nil] exception if model invocation failed
      def initialize(agent:, invocation_state: {}, stop_reason: nil, message: nil, exception: nil)
        super(agent: agent)
        @invocation_state = invocation_state
        @stop_reason = stop_reason
        @message = message
        @exception = exception
        @retry = false
      end

      def reverse_callbacks?
        true
      end
    end
  end
end
