# frozen_string_literal: true

require "time"

module Strands
  module Telemetry
    # Tracks token usage, latency, and tool call statistics per invocation.
    #
    # This class provides an interface for collecting performance metrics
    # without requiring any external telemetry dependencies. It tracks:
    # - Token usage (input, output, total, cached)
    # - Latency per model call
    # - Tool call counts and durations
    # - Event loop cycle counts and durations
    #
    # @example
    #   metrics = Strands::Telemetry::Metrics.new
    #   metrics.start_invocation
    #   metrics.record_usage(input_tokens: 100, output_tokens: 50)
    #   metrics.record_latency(150.5)
    #   metrics.record_tool_call("calculator", duration: 0.5, success: true)
    #   summary = metrics.summary
    #
    class Metrics
      # @return [Integer] total input tokens across all invocations
      attr_reader :total_input_tokens

      # @return [Integer] total output tokens across all invocations
      attr_reader :total_output_tokens

      # @return [Integer] total tokens across all invocations
      attr_reader :total_tokens

      # @return [Float] accumulated latency in milliseconds
      attr_reader :total_latency_ms

      # @return [Integer] total number of model calls
      attr_reader :model_call_count

      # @return [Integer] total number of event loop cycles
      attr_reader :cycle_count

      # @return [Hash<String, ToolMetric>] per-tool metrics
      attr_reader :tool_metrics

      # @return [Array<InvocationMetric>] per-invocation metrics
      attr_reader :invocations

      def initialize
        @total_input_tokens = 0
        @total_output_tokens = 0
        @total_tokens = 0
        @total_latency_ms = 0.0
        @model_call_count = 0
        @cycle_count = 0
        @tool_metrics = {}
        @invocations = []
        @current_invocation = nil
      end

      # Start tracking a new agent invocation.
      #
      # @return [void]
      def start_invocation
        @current_invocation = InvocationMetric.new
        @invocations << @current_invocation
      end

      # Record token usage from a model call.
      #
      # @param input_tokens [Integer] input/prompt tokens
      # @param output_tokens [Integer] output/completion tokens
      # @param cache_read_tokens [Integer] cached read tokens
      # @param cache_write_tokens [Integer] cached write tokens
      # @return [void]
      def record_usage(input_tokens: 0, output_tokens: 0, cache_read_tokens: 0, cache_write_tokens: 0)
        total = input_tokens + output_tokens

        @total_input_tokens += input_tokens
        @total_output_tokens += output_tokens
        @total_tokens += total
        @model_call_count += 1

        return unless @current_invocation

        @current_invocation.input_tokens += input_tokens
        @current_invocation.output_tokens += output_tokens
        @current_invocation.total_tokens += total
        @current_invocation.cache_read_tokens += cache_read_tokens
        @current_invocation.cache_write_tokens += cache_write_tokens
        @current_invocation.model_call_count += 1
      end

      # Record latency from a model call.
      #
      # @param latency_ms [Float] latency in milliseconds
      # @return [void]
      def record_latency(latency_ms)
        @total_latency_ms += latency_ms
        return unless @current_invocation

        @current_invocation.total_latency_ms += latency_ms
      end

      # Record a tool call and its outcome.
      #
      # @param tool_name [String] name of the tool
      # @param duration [Float] execution time in seconds
      # @param success [Boolean] whether the call succeeded
      # @return [void]
      def record_tool_call(tool_name, duration:, success:)
        metric = (@tool_metrics[tool_name] ||= ToolMetric.new(tool_name))
        metric.record(duration: duration, success: success)
      end

      # Record a completed event loop cycle.
      #
      # @param duration [Float] cycle duration in seconds
      # @return [void]
      def record_cycle(duration:)
        @cycle_count += 1
        return unless @current_invocation

        @current_invocation.cycle_count += 1
        @current_invocation.cycle_durations << duration
      end

      # Generate a summary of all collected metrics.
      #
      # @return [Hash]
      def summary
        {
          total_input_tokens: @total_input_tokens,
          total_output_tokens: @total_output_tokens,
          total_tokens: @total_tokens,
          total_latency_ms: @total_latency_ms,
          model_call_count: @model_call_count,
          cycle_count: @cycle_count,
          tool_metrics: @tool_metrics.transform_values(&:to_h),
          invocations: @invocations.map(&:to_h)
        }
      end

      # Reset all metrics to initial state.
      #
      # @return [void]
      def reset!
        @total_input_tokens = 0
        @total_output_tokens = 0
        @total_tokens = 0
        @total_latency_ms = 0.0
        @model_call_count = 0
        @cycle_count = 0
        @tool_metrics = {}
        @invocations = []
        @current_invocation = nil
      end
    end

    # Metrics for a single tool.
    #
    # @attr_reader name [String] tool name
    # @attr_reader call_count [Integer] total calls
    # @attr_reader success_count [Integer] successful calls
    # @attr_reader error_count [Integer] failed calls
    # @attr_reader total_duration [Float] total execution time in seconds
    class ToolMetric
      attr_reader :name, :call_count, :success_count, :error_count, :total_duration

      # @param name [String] the tool name
      def initialize(name)
        @name = name
        @call_count = 0
        @success_count = 0
        @error_count = 0
        @total_duration = 0.0
      end

      # Record a tool call.
      #
      # @param duration [Float] execution time in seconds
      # @param success [Boolean] whether the call succeeded
      def record(duration:, success:)
        @call_count += 1
        @total_duration += duration
        if success
          @success_count += 1
        else
          @error_count += 1
        end
      end

      # Average duration per call.
      #
      # @return [Float]
      def average_duration
        return 0.0 if @call_count.zero?

        @total_duration / @call_count
      end

      # Success rate as a float between 0 and 1.
      #
      # @return [Float]
      def success_rate
        return 0.0 if @call_count.zero?

        @success_count.to_f / @call_count
      end

      # Convert to hash representation.
      #
      # @return [Hash]
      def to_h
        {
          name: @name,
          call_count: @call_count,
          success_count: @success_count,
          error_count: @error_count,
          total_duration: @total_duration,
          average_duration: average_duration,
          success_rate: success_rate
        }
      end
    end

    # Metrics for a single agent invocation.
    #
    # @attr_accessor input_tokens [Integer]
    # @attr_accessor output_tokens [Integer]
    # @attr_accessor total_tokens [Integer]
    # @attr_accessor cache_read_tokens [Integer]
    # @attr_accessor cache_write_tokens [Integer]
    # @attr_accessor total_latency_ms [Float]
    # @attr_accessor model_call_count [Integer]
    # @attr_accessor cycle_count [Integer]
    # @attr_accessor cycle_durations [Array<Float>]
    class InvocationMetric
      attr_accessor :input_tokens, :output_tokens, :total_tokens,
                    :cache_read_tokens, :cache_write_tokens,
                    :total_latency_ms, :model_call_count,
                    :cycle_count, :cycle_durations

      def initialize
        @input_tokens = 0
        @output_tokens = 0
        @total_tokens = 0
        @cache_read_tokens = 0
        @cache_write_tokens = 0
        @total_latency_ms = 0.0
        @model_call_count = 0
        @cycle_count = 0
        @cycle_durations = []
      end

      # Convert to hash representation.
      #
      # @return [Hash]
      def to_h
        {
          input_tokens: @input_tokens,
          output_tokens: @output_tokens,
          total_tokens: @total_tokens,
          cache_read_tokens: @cache_read_tokens,
          cache_write_tokens: @cache_write_tokens,
          total_latency_ms: @total_latency_ms,
          model_call_count: @model_call_count,
          cycle_count: @cycle_count,
          cycle_durations: @cycle_durations
        }
      end
    end
  end
end
