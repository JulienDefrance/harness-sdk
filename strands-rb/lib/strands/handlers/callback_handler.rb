# frozen_string_literal: true

module Strands
  module Handlers
    # Base class for callback handlers that process streaming events.
    #
    # Callback handlers receive streaming data from the model and can format,
    # display, or process it. They must respond to #call with keyword arguments.
    #
    # @example Custom handler
    #   class MyHandler < Strands::Handlers::CallbackHandler
    #     def call(**kwargs)
    #       data = kwargs[:data]
    #       puts data if data && !data.empty?
    #     end
    #   end
    #
    class CallbackHandler
      # Process a streaming event.
      #
      # @param kwargs [Hash] event data including:
      #   - :data [String] text content to stream
      #   - :complete [Boolean] whether this is the final chunk
      #   - :event [Object] the raw streaming event
      #   - :tool_use [Object] tool use information
      # @return [void]
      def call(**kwargs)
        raise NotImplementedError, "#{self.class}#call must be implemented"
      end
    end
  end
end
