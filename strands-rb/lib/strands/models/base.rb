# frozen_string_literal: true

module Strands
  module Models
    # Abstract interface for model providers.
    #
    # Include this module in any model class to define the contract.
    # Implementing classes must override #stream, #update_config, and #get_config.
    #
    # @example Implementing a custom model
    #   class MyModel
    #     include Strands::Models::Base
    #
    #     def stream(messages, system_prompt: nil, tools: nil, tool_choice: nil, **kwargs)
    #       # yield StreamEvent objects
    #     end
    #
    #     def update_config(**opts)
    #       @config.merge!(opts)
    #     end
    #
    #     def get_config
    #       @config.dup
    #     end
    #   end
    #
    module Base
      # Stream a conversation with the model.
      #
      # This method handles the full lifecycle of interacting with the model:
      # 1. Format the messages, tool specs, and configuration into a request
      # 2. Send the request to the model
      # 3. Yield formatted StreamEvent objects one at a time
      #
      # @param messages [Array<Hash>] list of message objects to process
      # @param system_prompt [String, nil] system prompt for context
      # @param tools [Array<Strands::Types::Tools::ToolSpec>, nil] available tool specifications
      # @param tool_choice [Object, nil] tool selection strategy
      # @param kwargs [Hash] additional keyword arguments
      # @yieldparam event [Strands::Types::Streaming::StreamEvent] a stream event
      # @return [void]
      # @raise [NotImplementedError] if not overridden by the implementing class
      def stream(messages, system_prompt: nil, tools: nil, tool_choice: nil, **kwargs)
        raise NotImplementedError, "#{self.class}#stream must be implemented"
      end

      # Update the model configuration with the provided options.
      #
      # @param opts [Hash] configuration key-value pairs to merge
      # @return [void]
      # @raise [NotImplementedError] if not overridden by the implementing class
      def update_config(**opts)
        raise NotImplementedError, "#{self.class}#update_config must be implemented"
      end

      # Return the current model configuration.
      #
      # @return [Hash] the model configuration
      # @raise [NotImplementedError] if not overridden by the implementing class
      def get_config
        raise NotImplementedError, "#{self.class}#get_config must be implemented"
      end

      # Whether the model manages conversation state server-side.
      #
      # @return [Boolean] false by default
      def stateful?
        false
      end
    end
  end
end
