# frozen_string_literal: true

module Strands
  module Types
    # Content-related type definitions for the SDK.
    #
    # This module defines the types used to represent messages, content blocks,
    # and other content-related structures. These types are modeled after the
    # Bedrock API.
    module Content
      # Valid message roles
      ROLES = %i[user assistant].freeze

      # Text content to be evaluated by guardrails.
      #
      # @attr text [String] the input text
      # @attr qualifiers [Array<String>, nil] qualifiers describing the text block
      GuardContentText = Struct.new(:text, :qualifiers, keyword_init: true)

      # Content block to be evaluated by guardrails.
      #
      # @attr text [GuardContentText] text within content block
      GuardContent = Struct.new(:text, keyword_init: true)

      # Reasoning text block from the model.
      #
      # @attr text [String, nil] the reasoning text
      # @attr signature [String, nil] verification token
      ReasoningTextBlock = Struct.new(:text, :signature, keyword_init: true)

      # Reasoning content block.
      #
      # @attr reasoning_text [ReasoningTextBlock, nil] the reasoning used
      # @attr redacted_content [String, nil] encrypted reasoning content
      ReasoningContentBlock = Struct.new(:reasoning_text, :redacted_content, keyword_init: true)

      # A cache point configuration for optimizing conversation history.
      #
      # @attr type [String] the type of cache point (typically "default")
      # @attr ttl [String, nil] optional TTL duration (e.g. "5m", "1h")
      CachePoint = Struct.new(:type, :ttl, keyword_init: true) do
        def initialize(type: "default", ttl: nil)
          super(type: type, ttl: ttl)
        end
      end

      # A block of content for a message that you pass to, or receive from, a model.
      #
      # ContentBlock uses a hash-like approach with typed accessors.
      # Only one content type should be set per block.
      #
      # @attr text [String, nil] text content
      # @attr tool_use [ToolUse, nil] tool use request
      # @attr tool_result [ToolResult, nil] tool execution result
      # @attr image [ImageContent, nil] image content
      # @attr document [DocumentContent, nil] document content
      # @attr video [VideoContent, nil] video content
      # @attr reasoning_content [ReasoningContentBlock, nil] reasoning content
      # @attr guard_content [GuardContent, nil] guardrail content
      # @attr cache_point [CachePoint, nil] cache point configuration
      # @attr citations_content [Hash, nil] citations for a document
      ContentBlock = Struct.new(
        :text,
        :tool_use,
        :tool_result,
        :image,
        :document,
        :video,
        :reasoning_content,
        :guard_content,
        :cache_point,
        :citations_content,
        keyword_init: true
      ) do
        # Returns the type of content this block contains.
        #
        # @return [Symbol, nil] the content type key
        def content_type
          members.find { |m| !self[m].nil? }
        end
      end

      # System content block for model instructions.
      #
      # @attr text [String, nil] system prompt text
      # @attr cache_point [CachePoint, nil] cache point configuration
      SystemContentBlock = Struct.new(:text, :cache_point, keyword_init: true)

      # Optional metadata attached to a message.
      # Not sent to model providers. Persisted in session storage.
      #
      # @attr usage [Usage, nil] token usage information
      # @attr metrics [Metrics, nil] performance metrics
      # @attr custom [Hash, nil] arbitrary user/framework metadata
      MessageMetadata = Struct.new(:usage, :metrics, :custom, keyword_init: true)

      # A message in a conversation with the agent.
      #
      # @attr role [Symbol] the role (:user or :assistant)
      # @attr content [Array<ContentBlock>] the message content blocks
      # @attr tracking_id [String, nil] durable UUID for the message
      # @attr metadata [MessageMetadata, nil] optional metadata
      Message = Struct.new(:role, :content, :tracking_id, :metadata, keyword_init: true) do
        def initialize(role:, content:, tracking_id: nil, metadata: nil)
          unless ROLES.include?(role)
            raise ArgumentError, "role must be one of: #{ROLES.join(', ')}"
          end

          super(role: role, content: content, tracking_id: tracking_id, metadata: metadata)
        end

        # Ensures the message has a tracking ID, generating one if needed.
        #
        # @return [String] the tracking ID
        def ensure_tracking_id!
          self.tracking_id ||= generate_tracking_id
        end

        private

        def generate_tracking_id
          require "securerandom"
          SecureRandom.uuid
        end
      end

      # Splits a system prompt into string and content block forms.
      #
      # @param system_prompt [String, Array<SystemContentBlock>, nil] the system prompt
      # @return [Array(String, Array<SystemContentBlock>)] tuple of string and content blocks
      def self.split_system_prompt(system_prompt)
        case system_prompt
        when String
          [system_prompt, [SystemContentBlock.new(text: system_prompt)]]
        when Array
          text_parts = system_prompt.filter_map(&:text)
          system_prompt_str = text_parts.empty? ? nil : text_parts.join("\n")
          [system_prompt_str, system_prompt]
        else
          [nil, nil]
        end
      end
    end
  end
end
