# frozen_string_literal: true

module Strands
  module Interventions
    # Bridges InterventionHandler instances to the Strands hook system.
    #
    # Registers one hook callback per lifecycle event type, dispatches to all
    # handlers that override that method in registration order, with
    # short-circuiting on Deny and accumulation for Guide.
    #
    # @example
    #   hook_registry = Strands::Hooks::Registry.new
    #   intervention_registry = Strands::Interventions::Registry.new(
    #     handlers: [my_handler],
    #     hook_registry: hook_registry
    #   )
    #
    class Registry
      # @return [Array<Handler>] registered handlers in evaluation order
      attr_reader :handlers

      # Initialize the registry and wire handlers into the hook system.
      #
      # @param handlers [Array<Handler>] intervention handlers in evaluation order
      # @param hook_registry [Strands::Hooks::Registry] the agent's hook registry
      # @raise [ArgumentError] if two handlers share the same name
      def initialize(handlers:, hook_registry:)
        validate_unique_names!(handlers)
        @handlers = handlers.dup.freeze
        register_hooks(hook_registry)
      end

      private

      def validate_unique_names!(handlers)
        seen = {}
        handlers.each do |h|
          name = h.name
          if seen.key?(name)
            raise ArgumentError, "Duplicate intervention handler name: '#{name}'"
          end

          seen[name] = true
        end
      end

      def overridden?(handler, method_name)
        handler.class.instance_method(method_name).owner != Handler
      end

      def register_hooks(hook_registry)
        register_lifecycle_hook(hook_registry, :before_invocation, Hooks::BeforeInvocationEvent,
                               Hooks::HookOrder::INTERVENTION_INPUT)
        register_lifecycle_hook(hook_registry, :before_tool_call, Hooks::BeforeToolCallEvent,
                               Hooks::HookOrder::INTERVENTION_INPUT)
        register_lifecycle_hook(hook_registry, :after_tool_call, Hooks::AfterToolCallEvent,
                               Hooks::HookOrder::INTERVENTION_OUTPUT)
        register_lifecycle_hook(hook_registry, :before_model_call, Hooks::BeforeModelCallEvent,
                               Hooks::HookOrder::INTERVENTION_INPUT)
        register_lifecycle_hook(hook_registry, :after_model_call, Hooks::AfterModelCallEvent,
                               Hooks::HookOrder::INTERVENTION_OUTPUT)
      end

      def register_lifecycle_hook(hook_registry, method_name, event_class, order)
        return unless @handlers.any? { |h| overridden?(h, method_name) }

        hook_registry.add_callback(event_class, order: order) do |event|
          dispatch(event, method_name)
        end
      end

      def dispatch(event, method_name)
        guides = []

        @handlers.each do |handler|
          next unless overridden?(handler, method_name)

          action = evaluate_handler(handler, method_name, event)
          next if action.nil?

          if action.is_a?(Guide)
            guides << [handler.name, action]
          else
            short_circuit = apply_action(event, action, method_name, handler.name)
            return if short_circuit
          end
        end

        # Apply accumulated guides
        return if guides.empty?

        feedback = guides.map { |name, g| "[#{name}] #{g.feedback}" }.join("\n")
        apply_action(event, Guide.new(feedback: feedback), method_name, "")
      end

      def evaluate_handler(handler, method_name, event)
        handler.public_send(method_name, event)
      rescue StandardError => e
        handle_error(handler, method_name, e)
      end

      def handle_error(handler, method_name, error)
        case handler.on_error
        when :throw
          raise error
        when :deny
          Deny.new(reason: "Handler threw: #{error.message}")
        when :proceed
          nil
        else
          raise error
        end
      end

      # Apply an action to an event. Returns true if short-circuiting should occur.
      def apply_action(event, action, method_name, handler_name)
        case method_name
        when :before_invocation
          apply_before_invocation(event, action)
        when :before_tool_call
          apply_before_tool_call(event, action)
        when :after_tool_call
          apply_after_tool_call(event, action)
        when :before_model_call
          apply_before_model_call(event, action)
        when :after_model_call
          apply_after_model_call(event, action)
        else
          false
        end
      end

      def apply_before_invocation(event, action)
        case action
        when Deny
          event.cancel = "DENIED: #{action.reason}"
          true
        when Guide
          event.cancel = "GUIDANCE: #{action.feedback}"
          false
        when Transform
          action.apply.call(event)
          false
        when Proceed
          false
        else
          false
        end
      end

      def apply_before_tool_call(event, action)
        case action
        when Deny
          event.cancel_tool = "DENIED: #{action.reason}"
          true
        when Guide
          event.cancel_tool = "GUIDANCE: #{action.feedback}"
          false
        when Transform
          action.apply.call(event)
          false
        when Proceed
          false
        else
          false
        end
      end

      def apply_after_tool_call(event, action)
        case action
        when Transform
          action.apply.call(event)
          false
        when Proceed
          false
        else
          false
        end
      end

      def apply_before_model_call(event, action)
        case action
        when Deny
          event.cancel = "DENIED: #{action.reason}"
          true
        when Guide
          # Inject feedback - in full implementation this would add to agent.messages
          false
        when Transform
          action.apply.call(event)
          false
        when Proceed
          false
        else
          false
        end
      end

      def apply_after_model_call(event, action)
        case action
        when Guide
          event.retry = true
          false
        when Transform
          action.apply.call(event)
          false
        when Proceed
          false
        else
          false
        end
      end
    end
  end
end
