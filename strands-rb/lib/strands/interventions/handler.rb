# frozen_string_literal: true

module Strands
  module Interventions
    # Base class for intervention handlers.
    #
    # Subclasses must implement `#name` and override the lifecycle methods
    # they care about. Default implementations return Proceed.new.
    # The framework detects which methods are overridden and only calls those.
    #
    # @example
    #   class AuthorizationHandler < Strands::Interventions::Handler
    #     def name
    #       "authorization"
    #     end
    #
    #     def before_tool_call(event)
    #       if authorized?(event)
    #         Strands::Interventions::Proceed.new
    #       else
    #         Strands::Interventions::Deny.new(reason: "Not authorized")
    #       end
    #     end
    #   end
    #
    class Handler
      # A stable string identifier for the handler.
      # Must be unique across all handlers in an intervention registry.
      #
      # @return [String]
      # @raise [NotImplementedError] if not implemented
      def name
        raise NotImplementedError, "#{self.class}#name must be implemented"
      end

      # What to do when this handler raises an error.
      # Possible values: :throw, :proceed, :deny
      #
      # @return [Symbol] the error handling strategy
      def on_error
        :throw
      end

      # Called before an agent invocation begins.
      #
      # @param event [Strands::Hooks::BeforeInvocationEvent]
      # @return [Proceed, Deny, Guide, Transform]
      def before_invocation(event)
        Proceed.new
      end

      # Called before a tool is executed.
      #
      # @param event [Strands::Hooks::BeforeToolCallEvent]
      # @return [Proceed, Deny, Guide, Transform]
      def before_tool_call(event)
        Proceed.new
      end

      # Called after a tool execution completes.
      #
      # @param event [Strands::Hooks::AfterToolCallEvent]
      # @return [Proceed, Transform]
      def after_tool_call(event)
        Proceed.new
      end

      # Called before the model is invoked.
      #
      # @param event [Strands::Hooks::BeforeModelCallEvent]
      # @return [Proceed, Deny, Guide, Transform]
      def before_model_call(event)
        Proceed.new
      end

      # Called after the model invocation completes.
      #
      # @param event [Strands::Hooks::AfterModelCallEvent]
      # @return [Proceed, Guide, Transform]
      def after_model_call(event)
        Proceed.new
      end
    end
  end
end
