# frozen_string_literal: true

module Strands
  module Agent
    # Base class for conversation managers.
    #
    # Conversation managers control how the message history is trimmed
    # or transformed before being sent to the model. This helps manage
    # context window limits.
    #
    # @example Custom manager
    #   class MyManager < Strands::Agent::ConversationManager
    #     def apply(messages, model:)
    #       messages.last(10)
    #     end
    #   end
    #
    class ConversationManager
      # Apply conversation management to the messages.
      #
      # @param messages [Array<Hash>] the current message history
      # @param model [Object] the model instance (for context window info)
      # @return [Array<Hash>] the trimmed/transformed messages
      def apply(messages, model: nil)
        raise NotImplementedError, "#{self.class}#apply must be implemented"
      end
    end

    # No-op conversation manager that passes messages through unchanged.
    #
    # @example
    #   manager = Strands::Agent::NullConversationManager.new
    #   manager.apply(messages) # => messages (unchanged)
    #
    class NullConversationManager < ConversationManager
      # Returns messages unchanged.
      #
      # @param messages [Array<Hash>] the current message history
      # @param model [Object, nil] the model (unused)
      # @return [Array<Hash>]
      def apply(messages, model: nil)
        messages
      end
    end

    # Sliding window conversation manager that keeps the most recent messages.
    #
    # Preserves the first user-assistant pair (often contains important context)
    # and keeps up to `window_size` most recent messages.
    #
    # @example
    #   manager = Strands::Agent::SlidingWindowConversationManager.new(window_size: 20)
    #   trimmed = manager.apply(long_history)
    #
    class SlidingWindowConversationManager < ConversationManager
      # @return [Integer] maximum number of messages to retain
      attr_reader :window_size

      # @return [Boolean] whether to always preserve the first message pair
      attr_reader :preserve_first_pair

      # Creates a new SlidingWindowConversationManager.
      #
      # @param window_size [Integer] max messages to keep (default: 40)
      # @param preserve_first_pair [Boolean] keep first user+assistant pair (default: true)
      def initialize(window_size: 40, preserve_first_pair: true)
        @window_size = window_size
        @preserve_first_pair = preserve_first_pair
      end

      # Apply sliding window trimming to messages.
      #
      # @param messages [Array<Hash>] the current message history
      # @param model [Object, nil] the model (unused)
      # @return [Array<Hash>] trimmed messages within the window
      def apply(messages, model: nil)
        return messages if messages.length <= @window_size

        if @preserve_first_pair && messages.length >= 2
          # Keep first pair + recent window
          first_pair = messages[0, 2]
          remaining_window = @window_size - 2
          return first_pair if remaining_window <= 0

          recent = messages.last(remaining_window)
          first_pair + recent
        else
          messages.last(@window_size)
        end
      end
    end
  end
end
