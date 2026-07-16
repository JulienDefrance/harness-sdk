# frozen_string_literal: true

module Strands
  # Observability via OpenTelemetry tracing and metrics collection.
  module Telemetry
    autoload :Tracer, "strands/telemetry/tracer"
    autoload :Span, "strands/telemetry/tracer"
    autoload :Metrics, "strands/telemetry/metrics"
    autoload :ToolMetric, "strands/telemetry/metrics"
    autoload :InvocationMetric, "strands/telemetry/metrics"
  end
end
