# frozen_string_literal: true

module Strands
  module Types
    # Streaming-related type definitions for the SDK.
    #
    # These types represent events emitted during streaming model responses.
    # Modeled after the Bedrock API streaming protocol.
    module Streaming
      # Event signaling the start of a message in a streaming response.
      #
      # @attr role [Symbol] the role of the message sender (:user or :assistant)
      MessageStartEvent = Struct.new(:role, keyword_init: true)

      # Information about a tool use at content block start.
      #
      # @attr name [String] tool name
      # @attr tool_use_id [String] tool use identifier
      # @attr reasoning_signature [String, nil] reasoning verification token
      ContentBlockStartToolUse = Struct.new(:name, :tool_use_id, :reasoning_signature, keyword_init: true)

      # Content block start information.
      #
      # @attr tool_use [ContentBlockStartToolUse, nil] tool use info at start
      ContentBlockStart = Struct.new(:tool_use, keyword_init: true)

      # Event signaling the start of a content block in a streaming response.
      #
      # @attr content_block_index [Integer, nil] index of the content block
      # @attr start [ContentBlockStart, nil] information about the content block
      ContentBlockStartEvent = Struct.new(:content_block_index, :start, keyword_init: true)

      # Text content delta in a streaming response.
      #
      # @attr text [String] the text fragment
      ContentBlockDeltaText = Struct.new(:text, keyword_init: true)

      # Tool use input delta in a streaming response.
      #
      # @attr input [String] the tool input fragment
      # @attr tool_use_id [String, nil] optional tool use identifier
      # @attr name [String, nil] optional tool name
      ContentBlockDeltaToolUse = Struct.new(:input, :tool_use_id, :name, keyword_init: true)

      # Reasoning content block delta.
      #
      # @attr text [String, nil] reasoning text fragment
      # @attr signature [String, nil] verification token
      # @attr redacted_content [String, nil] encrypted reasoning content
      ReasoningContentBlockDelta = Struct.new(:text, :signature, :redacted_content, keyword_init: true)

      # A block of content in a streaming response delta.
      #
      # @attr text [String, nil] text fragment
      # @attr tool_use [ContentBlockDeltaToolUse, nil] tool use input fragment
      # @attr reasoning_content [ReasoningContentBlockDelta, nil] reasoning delta
      ContentBlockDelta = Struct.new(:text, :tool_use, :reasoning_content, keyword_init: true)

      # Event containing a delta update for a content block.
      #
      # @attr content_block_index [Integer, nil] index of the content block
      # @attr delta [ContentBlockDelta] the incremental content update
      ContentBlockDeltaEvent = Struct.new(:content_block_index, :delta, keyword_init: true)

      # Event signaling the end of a content block.
      #
      # @attr content_block_index [Integer, nil] index of the content block
      ContentBlockStopEvent = Struct.new(:content_block_index, keyword_init: true)

      # Event signaling the end of a message.
      #
      # @attr stop_reason [Symbol, nil] the reason the model stopped generating
      # @attr additional_model_response_fields [Object, nil] additional response fields
      MessageStopEvent = Struct.new(:stop_reason, :additional_model_response_fields, keyword_init: true)

      # Event containing metadata about the streaming response.
      #
      # @attr metrics [EventLoop::Metrics, nil] performance metrics
      # @attr usage [EventLoop::Usage, nil] token usage information
      # @attr trace [Object, nil] trace information for debugging
      MetadataEvent = Struct.new(:metrics, :usage, :trace, keyword_init: true)

      # Base event for exceptions in a streaming response.
      #
      # @attr message [String] the error message
      ExceptionEvent = Struct.new(:message, keyword_init: true)

      # Event for model streaming errors.
      #
      # @attr message [String] error message
      # @attr original_message [String] original error from provider
      # @attr original_status_code [Integer] HTTP status code from provider
      ModelStreamErrorEvent = Struct.new(:message, :original_message, :original_status_code, keyword_init: true)

      # A stream event envelope wrapping the various event types.
      #
      # Only one event type should be set per StreamEvent instance.
      #
      # @attr message_start [MessageStartEvent, nil]
      # @attr content_block_start [ContentBlockStartEvent, nil]
      # @attr content_block_delta [ContentBlockDeltaEvent, nil]
      # @attr content_block_stop [ContentBlockStopEvent, nil]
      # @attr message_stop [MessageStopEvent, nil]
      # @attr metadata [MetadataEvent, nil]
      # @attr internal_server_exception [ExceptionEvent, nil]
      # @attr model_stream_error_exception [ModelStreamErrorEvent, nil]
      # @attr service_unavailable_exception [ExceptionEvent, nil]
      # @attr throttling_exception [ExceptionEvent, nil]
      # @attr validation_exception [ExceptionEvent, nil]
      StreamEvent = Struct.new(
        :message_start,
        :content_block_start,
        :content_block_delta,
        :content_block_stop,
        :message_stop,
        :metadata,
        :internal_server_exception,
        :model_stream_error_exception,
        :service_unavailable_exception,
        :throttling_exception,
        :validation_exception,
        keyword_init: true
      ) do
        # Returns the type of event this envelope contains.
        #
        # @return [Symbol, nil] the event type key
        def event_type
          members.find { |m| !self[m].nil? }
        end
      end
    end
  end
end
