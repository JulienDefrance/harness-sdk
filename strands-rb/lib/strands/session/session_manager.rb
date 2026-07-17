# frozen_string_literal: true

module Strands
  module Session
    # Abstract base class for session managers that persist agent conversations.
    #
    # Session managers implement the Hooks::Provider interface to hook into
    # agent lifecycle events (initialization, message added, after invocation)
    # and persist the conversation state accordingly.
    #
    # Subclasses must implement:
    # - #initialize_session(agent)
    # - #append_message(message, agent)
    # - #sync_agent(agent)
    # - #restore(agent)
    #
    # @example
    #   class MySessionManager < Strands::Session::Manager
    #     def initialize_session(agent)
    #       # Restore agent state from storage
    #     end
    #
    #     def append_message(message, agent)
    #       # Persist a new message
    #     end
    #
    #     def sync_agent(agent)
    #       # Sync full agent state
    #     end
    #
    #     def restore(agent)
    #       # Restore full state
    #     end
    #   end
    #
    class Manager
      include Hooks::Provider

      # Register hooks for persisting the agent to the session.
      #
      # Hooks into:
      # - AgentInitializedEvent: calls #initialize_session to restore agent state
      # - MessageAddedEvent: calls #append_message to persist each message
      # - AfterInvocationEvent: calls #sync_agent to capture state updates
      #
      # @param registry [Strands::Hooks::Registry] the hook registry
      def register_hooks(registry)
        registry.add_callback(Hooks::AgentInitializedEvent) do |event|
          initialize_session(event.agent)
        end

        registry.add_callback(Hooks::MessageAddedEvent) do |event|
          append_message(event.message, event.agent)
        end

        registry.add_callback(Hooks::MessageAddedEvent) do |event|
          sync_agent(event.agent)
        end

        registry.add_callback(Hooks::AfterInvocationEvent) do |event|
          sync_agent(event.agent)
        end
      end

      # Initialize the session for an agent, restoring any persisted state.
      #
      # @param agent [Object] the agent instance
      # @raise [NotImplementedError] if not overridden
      def initialize_session(agent)
        raise NotImplementedError, "#{self.class}#initialize_session must be implemented"
      end

      # Append a message to the session's persistent storage.
      #
      # @param message [Hash] the message to persist
      # @param agent [Object] the agent instance
      # @raise [NotImplementedError] if not overridden
      def append_message(message, agent)
        raise NotImplementedError, "#{self.class}#append_message must be implemented"
      end

      # Sync the full agent state to session storage.
      #
      # @param agent [Object] the agent instance
      # @raise [NotImplementedError] if not overridden
      def sync_agent(agent)
        raise NotImplementedError, "#{self.class}#sync_agent must be implemented"
      end

      # Restore the agent state from session storage.
      #
      # @param agent [Object] the agent instance
      # @raise [NotImplementedError] if not overridden
      def restore(agent)
        raise NotImplementedError, "#{self.class}#restore must be implemented"
      end
    end
  end
end
