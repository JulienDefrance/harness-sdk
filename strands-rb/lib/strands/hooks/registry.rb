# frozen_string_literal: true

module Strands
  module Hooks
    # Named constants for hook execution priority.
    # Lower values execute first. Hooks with the same order preserve registration order.
    module HookOrder
      SDK_FIRST = -100
      INTERVENTION_OUTPUT = -90
      BEFORE = -50
      DEFAULT = 0
      NORMAL = 0
      AFTER = 50
      INTERVENTION_INPUT = 90
      SDK_LAST = 100
    end

    # Registry for managing hook callbacks associated with event types.
    #
    # The HookRegistry maintains a mapping of event types to callback functions
    # and provides methods for registering callbacks and invoking them when
    # events occur.
    #
    # @example
    #   registry = Strands::Hooks::Registry.new
    #   registry.add_callback(Strands::Hooks::BeforeModelCallEvent, order: HookOrder::DEFAULT) do |event|
    #     puts "Model called for agent: #{event.agent}"
    #   end
    #   registry.fire(event)
    #
    class Registry
      def initialize
        @callbacks = {} # Hash[Class => Array[{callback:, order:}]]
      end

      # Register a callback for a specific event type.
      #
      # @param event_class [Class] the event class to listen for
      # @param order [Integer] execution priority (lower executes first)
      # @param block [Proc] the callback to invoke
      # @return [void]
      def add_callback(event_class, order: HookOrder::DEFAULT, &block)
        raise ArgumentError, "A block is required" unless block_given?
        raise ArgumentError, "event_class must be a Class" unless event_class.is_a?(Class)

        entries = (@callbacks[event_class] ||= [])
        entry = { callback: block, order: order }

        # Insert in sorted order by priority (stable: preserves registration order within same priority)
        insert_index = entries.bsearch_index { |e| e[:order] > order } || entries.length
        entries.insert(insert_index, entry)
      end

      # Register all callbacks from a hook provider.
      #
      # @param provider [Object] an object responding to #register_hooks(registry)
      # @return [void]
      def add_hook(provider)
        raise ArgumentError, "Provider must respond to #register_hooks" unless provider.respond_to?(:register_hooks)

        provider.register_hooks(self)
      end

      # Fire an event, invoking all registered callbacks for its type.
      #
      # For events where `reverse_callbacks?` is true, callbacks within the
      # same priority group are invoked in reverse registration order.
      #
      # @param event [Strands::Hooks::Event] the event to dispatch
      # @return [void]
      def fire(event)
        event_class = event.class
        entries = @callbacks[event_class] || []

        if event.reverse_callbacks?
          # Group by order, then reverse within each group
          grouped = entries.group_by { |e| e[:order] }
          grouped.keys.sort.each do |order|
            grouped[order].reverse_each do |entry|
              entry[:callback].call(event)
            end
          end
        else
          entries.each do |entry|
            entry[:callback].call(event)
          end
        end
      end

      # Check if the registry has any registered callbacks.
      #
      # @return [Boolean]
      def callbacks?
        @callbacks.any? { |_k, v| !v.empty? }
      end

      # Get the number of callbacks registered for a specific event type.
      #
      # @param event_class [Class] the event class
      # @return [Integer]
      def callback_count(event_class)
        (@callbacks[event_class] || []).length
      end

      # Get all callbacks registered for a given event type in execution order.
      #
      # @param event_class [Class] the event class
      # @return [Array<Proc>]
      def callbacks_for(event_class)
        (@callbacks[event_class] || []).map { |e| e[:callback] }
      end
    end
  end
end
