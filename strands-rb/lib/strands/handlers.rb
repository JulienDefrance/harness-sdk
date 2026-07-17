# frozen_string_literal: true

module Strands
  # Callback handlers for streaming output and agent events.
  module Handlers
    autoload :CallbackHandler, "strands/handlers/callback_handler"
    autoload :Printing, "strands/handlers/printing"
    autoload :Null, "strands/handlers/null"

    # Convenience method to create a printing callback handler.
    #
    # @param kwargs [Hash] options passed to Printing.new
    # @return [Printing]
    def self.printing(**kwargs)
      Printing.new(**kwargs)
    end

    # Convenience method to create a null callback handler.
    #
    # @return [Null]
    def self.null
      Null.new
    end
  end
end
