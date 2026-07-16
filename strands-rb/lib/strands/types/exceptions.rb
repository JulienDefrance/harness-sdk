# frozen_string_literal: true

module Strands
  module Types
    # Custom exception types for the SDK.
    #
    # All exceptions inherit from Strands::Error (which inherits from StandardError),
    # allowing rescue of all SDK errors with `rescue Strands::Error`.
    module Exceptions
      # Exception raised by the event loop.
      # Wraps an original exception with optional request state.
      class EventLoopError < Strands::Error
        # @return [Exception] the original exception that was raised
        attr_reader :original_exception

        # @return [Hash] the state of the request at the time of the exception
        attr_reader :request_state

        # @param original_exception [Exception] the original exception
        # @param request_state [Hash] optional request state
        def initialize(original_exception, request_state: {})
          @original_exception = original_exception
          @request_state = request_state
          super(original_exception.to_s)
        end
      end

      # Exception raised when the context window is exceeded.
      # This occurs when combined conversation history, system prompt,
      # and current message exceed the model's maximum context size.
      class ContextWindowOverflowError < Strands::Error; end

      # Exception raised when the model is throttled by the service.
      class ModelThrottledError < Strands::Error; end

      # Exception raised when the model reaches its maximum token generation limit.
      # The partial message is automatically added to agent.messages and the
      # conversation can be continued by calling the agent again.
      class MaxTokensReachedError < Strands::Error; end

      # Exception raised when the MCP server fails to initialize properly.
      class MCPClientInitializationError < Strands::Error; end

      # Exception raised when session operations fail.
      class SessionError < Strands::Error; end

      # Exception raised when snapshot operations fail.
      class SnapshotError < Strands::Error; end

      # Exception raised when a model provider's native token counting API fails.
      # Used as internal control flow within provider count_tokens overrides.
      class ProviderTokenCountError < Strands::Error; end

      # Exception raised when a tool provider fails to load or cleanup tools.
      class ToolProviderError < Strands::Error; end

      # Exception raised when structured output validation fails.
      class StructuredOutputError < Strands::Error; end

      # Exception raised when concurrent invocations are attempted on an agent.
      class ConcurrencyError < Strands::Error; end

      # Exception raised when a storage operation fails.
      # Wraps backend-specific errors with a uniform type.
      class StorageError < Strands::Error; end

      # Exception raised when one or more memory store operations fail.
      class AggregateMemoryError < Strands::Error
        # @return [Array<Exception>] the underlying exceptions
        attr_reader :errors

        # @param message [String] description of the aggregate failure
        # @param errors [Array<Exception>] the underlying exceptions
        def initialize(message, errors: [])
          @errors = errors
          super(message)
        end
      end
    end
  end
end
