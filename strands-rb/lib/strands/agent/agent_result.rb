# frozen_string_literal: true

module Strands
  module Agent
    # Result returned by Agent#call representing the outcome of an invocation.
    #
    # @attr stop_reason [Symbol] reason the agent stopped (:end_turn, :max_tokens, :tool_use, :limit_turns, etc.)
    # @attr message [Hash, nil] the final assistant message
    # @attr metrics [Hash] metrics about the invocation (token usage, latency)
    # @attr state [Hash] arbitrary state accumulated during the invocation
    #
    # @example
    #   result = agent.call("Hello")
    #   result.stop_reason # => :end_turn
    #   result.message     # => { role: :assistant, content: [{ text: "Hi!" }] }
    #   result.text        # => "Hi!"
    #
    Result = Struct.new(:stop_reason, :message, :metrics, :state, keyword_init: true) do
      def initialize(stop_reason:, message: nil, metrics: {}, state: {})
        super(stop_reason: stop_reason, message: message, metrics: metrics, state: state)
      end

      # Extract the text content from the result message.
      #
      # @return [String] concatenated text from all text content blocks
      def text
        return "" unless message

        content = message[:content] || []
        content.filter_map { |block| block[:text] }.join
      end

      # Whether the agent stopped normally (end_turn).
      #
      # @return [Boolean]
      def success?
        stop_reason == :end_turn
      end

      # Extract tool use blocks from the result message.
      #
      # @return [Array<Types::Tools::ToolUse>]
      def tool_uses
        return [] unless message

        content = message[:content] || []
        content.filter_map { |block| block[:tool_use] }
      end

      # String representation for display.
      #
      # @return [String]
      def to_s
        text
      end

      # Inspect representation for debugging.
      #
      # @return [String]
      def inspect
        "#<Strands::Agent::Result stop_reason=#{stop_reason.inspect} text=#{text.inspect[0..50]}>"
      end
    end
  end
end
