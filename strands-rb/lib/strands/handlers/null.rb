# frozen_string_literal: true

module Strands
  module Handlers
    # No-op callback handler that discards all output.
    #
    # Use this handler when streaming output should be silently consumed
    # without any side effects.
    #
    # @example
    #   handler = Strands::Handlers::Null.new
    #   handler.call(data: "ignored", complete: false)
    #   # does nothing
    #
    class Null < CallbackHandler
      # Discards all event data.
      #
      # @param kwargs [Hash] event data (ignored)
      # @return [void]
      def call(**kwargs)
        # intentionally empty
      end
    end
  end
end
