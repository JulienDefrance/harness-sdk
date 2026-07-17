# frozen_string_literal: true

module Strands
  module Models
    # Shared module for building StreamEvent objects from provider event data.
    #
    # All model providers emit the same StreamEvent types. This module provides
    # the common factory method to avoid duplication across providers.
    #
    # @example Including in a provider
    #   class MyProvider
    #     include Strands::Models::Base
    #     include Strands::Models::StreamEventBuilder
    #
    #     def stream(messages, **opts)
    #       yield build_stream_event(:message_start, role: :assistant)
    #     end
    #   end
    #
    module StreamEventBuilder
      private

      # Build a StreamEvent with the given event type data.
      #
      # @param type [Symbol] the event type (:message_start, :content_block_start,
      #   :content_block_delta, :content_block_stop, :message_stop, :metadata)
      # @param kwargs [Hash] event-specific data
      # @return [Strands::Types::Streaming::StreamEvent]
      def build_stream_event(type, **kwargs)
        case type
        when :message_start
          Types::Streaming::StreamEvent.new(
            message_start: Types::Streaming::MessageStartEvent.new(role: kwargs[:role] || :assistant)
          )
        when :content_block_start
          Types::Streaming::StreamEvent.new(
            content_block_start: Types::Streaming::ContentBlockStartEvent.new(start: kwargs[:start])
          )
        when :content_block_delta
          Types::Streaming::StreamEvent.new(
            content_block_delta: Types::Streaming::ContentBlockDeltaEvent.new(delta: kwargs[:delta])
          )
        when :content_block_stop
          Types::Streaming::StreamEvent.new(
            content_block_stop: Types::Streaming::ContentBlockStopEvent.new
          )
        when :message_stop
          Types::Streaming::StreamEvent.new(
            message_stop: Types::Streaming::MessageStopEvent.new(stop_reason: kwargs[:stop_reason])
          )
        when :metadata
          Types::Streaming::StreamEvent.new(
            metadata: Types::Streaming::MetadataEvent.new(
              usage: kwargs[:usage],
              metrics: kwargs[:metrics]
            )
          )
        end
      end
    end
  end
end
