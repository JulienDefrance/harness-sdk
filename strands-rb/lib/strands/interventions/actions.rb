# frozen_string_literal: true

module Strands
  module Interventions
    # Allow the operation to continue unchanged.
    # Optionally carries a reason for debugging/logging.
    class Proceed
      # @return [String, nil] optional metadata for debugging
      attr_reader :reason

      # @param reason [String, nil] optional reason for proceeding
      def initialize(reason: nil)
        @reason = reason
      end

      # @return [String] the action type
      def type
        "proceed"
      end

      def ==(other)
        other.is_a?(Proceed) && other.reason == reason
      end
    end

    # Block the operation. The reason is communicated to the model
    # as the cancellation message.
    class Deny
      # @return [String] the reason for denial
      attr_reader :reason

      # @param reason [String] the denial reason
      def initialize(reason: "")
        @reason = reason
      end

      # @return [String] the action type
      def type
        "deny"
      end

      def ==(other)
        other.is_a?(Deny) && other.reason == reason
      end
    end

    # Provide feedback to steer behavior.
    # On before events, sets cancel so the model sees the feedback.
    # On after_model_call, the response is discarded and the model retries with feedback.
    class Guide
      # @return [String] the guidance feedback
      attr_reader :feedback

      # @return [String, nil] optional reason for the guidance
      attr_reader :reason

      # @param feedback [String] the guidance feedback message
      # @param reason [String, nil] optional reason
      def initialize(feedback: "", reason: nil)
        @feedback = feedback
        @reason = reason
      end

      # @return [String] the action type
      def type
        "guide"
      end

      def ==(other)
        other.is_a?(Guide) && other.feedback == feedback && other.reason == reason
      end
    end

    # Modify event content in-place.
    # The apply callable mutates the event before execution proceeds.
    # Later handlers in the pipeline see the transformed content.
    class Transform
      # @return [Proc] the transformation function
      attr_reader :apply

      # @return [String, nil] optional reason for the transformation
      attr_reader :reason

      # @param apply [Proc] a callable that receives the event and mutates it
      # @param reason [String, nil] optional reason
      def initialize(apply: ->(_event) {}, reason: nil)
        @apply = apply
        @reason = reason
      end

      # @return [String] the action type
      def type
        "transform"
      end

      def ==(other)
        other.is_a?(Transform) && other.reason == reason
      end
    end
  end
end
