# frozen_string_literal: true

module Strands
  module Hooks
    # Module defining the interface for hook providers.
    #
    # Hook providers offer a composable way to extend agent functionality by
    # subscribing to various events in the agent lifecycle. Include this module
    # in any class that needs to register hooks.
    #
    # @example
    #   class MyProvider
    #     include Strands::Hooks::Provider
    #
    #     def register_hooks(registry)
    #       registry.add_callback(Strands::Hooks::BeforeModelCallEvent) do |event|
    #         puts "Model called!"
    #       end
    #     end
    #   end
    #
    module Provider
      # Register callback functions for specific event types.
      #
      # @param registry [Strands::Hooks::Registry] the hook registry
      # @raise [NotImplementedError] if not implemented by the including class
      def register_hooks(registry)
        raise NotImplementedError, "#{self.class}#register_hooks must be implemented"
      end
    end
  end
end
