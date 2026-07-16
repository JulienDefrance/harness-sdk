# frozen_string_literal: true

module Strands
  module EventLoop
    # Configures retry behavior for transient model errors.
    #
    # Implements exponential backoff with jitter for retrying failed model calls.
    # Used by the event loop Cycle to determine delay between retry attempts.
    #
    # @example Default configuration
    #   strategy = Strands::EventLoop::RetryStrategy.new
    #   strategy.max_attempts # => 6
    #
    # @example Custom configuration
    #   strategy = Strands::EventLoop::RetryStrategy.new(
    #     max_attempts: 3,
    #     initial_delay: 2.0,
    #     max_delay: 60.0
    #   )
    #
    class RetryStrategy
      # @return [Integer] maximum number of attempts before giving up
      attr_reader :max_attempts

      # @return [Float] initial delay in seconds before the first retry
      attr_reader :initial_delay

      # @return [Float] maximum delay in seconds between retries
      attr_reader :max_delay

      # @return [Float] backoff multiplier applied each attempt
      attr_reader :backoff_factor

      # Default values matching the Python SDK
      DEFAULT_MAX_ATTEMPTS = 6
      DEFAULT_INITIAL_DELAY = 4.0
      DEFAULT_MAX_DELAY = 240.0
      DEFAULT_BACKOFF_FACTOR = 2.0

      # Creates a new RetryStrategy.
      #
      # @param max_attempts [Integer] maximum retry attempts (default: 6)
      # @param initial_delay [Float] initial delay in seconds (default: 4.0)
      # @param max_delay [Float] maximum delay cap in seconds (default: 240.0)
      # @param backoff_factor [Float] multiplier for exponential backoff (default: 2.0)
      def initialize(max_attempts: DEFAULT_MAX_ATTEMPTS, initial_delay: DEFAULT_INITIAL_DELAY,
                     max_delay: DEFAULT_MAX_DELAY, backoff_factor: DEFAULT_BACKOFF_FACTOR)
        @max_attempts = max_attempts
        @initial_delay = initial_delay.to_f
        @max_delay = max_delay.to_f
        @backoff_factor = backoff_factor.to_f
      end

      # Calculate the delay for a given attempt number.
      #
      # Uses exponential backoff: delay = initial_delay * (backoff_factor ** attempt)
      # Capped at max_delay. Adds jitter of up to 25% to prevent thundering herd.
      #
      # @param attempt [Integer] the current attempt number (0-based)
      # @return [Float] the delay in seconds
      def delay_for(attempt)
        raw_delay = @initial_delay * (@backoff_factor**attempt)
        capped_delay = [raw_delay, @max_delay].min
        # Add jitter (0% to 25% of the delay)
        jitter = capped_delay * rand * 0.25
        capped_delay + jitter
      end

      # Whether a retry should be attempted for the given attempt number.
      #
      # @param attempt [Integer] the current attempt number (0-based)
      # @return [Boolean] true if more attempts remain
      def should_retry?(attempt)
        attempt < @max_attempts - 1
      end
    end
  end
end
