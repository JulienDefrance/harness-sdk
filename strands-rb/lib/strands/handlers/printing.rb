# frozen_string_literal: true

module Strands
  module Handlers
    # Callback handler that prints streaming text output to stdout.
    #
    # Prints text deltas as they arrive and optionally displays tool use
    # information. This is the default handler used when no other is specified.
    #
    # @example
    #   handler = Strands::Handlers::Printing.new
    #   handler.call(data: "Hello", complete: false)
    #   # prints "Hello" without newline
    #
    #   handler.call(data: "", complete: true)
    #   # prints newline
    #
    class Printing < CallbackHandler
      # @return [Integer] count of tools invoked during this handler's lifetime
      attr_reader :tool_count

      # @return [Boolean] whether to print verbose tool use information
      attr_reader :verbose_tool_use

      # Creates a new PrintingCallbackHandler.
      #
      # @param output [IO] the output stream (default: $stdout)
      # @param verbose_tool_use [Boolean] print verbose tool call info (default: true)
      def initialize(output: $stdout, verbose_tool_use: true)
        @output = output
        @verbose_tool_use = verbose_tool_use
        @tool_count = 0
      end

      # Process a streaming event by printing text to the output.
      #
      # @param kwargs [Hash] event data
      # @return [void]
      def call(**kwargs)
        data = kwargs[:data]
        complete = kwargs[:complete] || false
        tool_use = kwargs[:tool_use]

        if data && !data.empty?
          if complete
            @output.puts data
          else
            @output.print data
          end
        elsif complete
          @output.puts ""
        end

        return unless tool_use && @verbose_tool_use

        @tool_count += 1
        tool_name = tool_use.respond_to?(:name) ? tool_use.name : tool_use.to_s
        @output.puts "\nTool ##{@tool_count}: #{tool_name}"
      end
    end
  end
end
