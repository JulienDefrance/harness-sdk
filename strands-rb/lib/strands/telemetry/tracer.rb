# frozen_string_literal: true

require "securerandom"
require "time"

module Strands
  module Telemetry
    # Span-based tracer providing an OpenTelemetry-compatible interface
    # without requiring the OpenTelemetry gem as a hard dependency.
    #
    # This tracer creates spans for agent operations (model calls, tool calls,
    # event loop cycles) and records attributes and events on them. When an
    # OpenTelemetry SDK is configured, a subclass or adapter can forward these
    # spans to the real OTel API.
    #
    # @example
    #   tracer = Strands::Telemetry::Tracer.new
    #   span = tracer.start_span("model_invoke", attributes: { model: "claude" })
    #   # ... perform work ...
    #   tracer.end_span(span)
    #
    class Tracer
      # @return [String] the service name for this tracer
      attr_reader :service_name

      # @param service_name [String] service name for spans
      def initialize(service_name: "strands-agents")
        @service_name = service_name
      end

      # Start a new span.
      #
      # @param name [String] the span name
      # @param parent [Span, nil] optional parent span
      # @param attributes [Hash] initial attributes
      # @param kind [Symbol] span kind (:internal, :client, :server)
      # @return [Span] the created span
      def start_span(name, parent: nil, attributes: {}, kind: :internal)
        Span.new(
          name: name,
          parent: parent,
          attributes: attributes.merge("gen_ai.system" => @service_name),
          kind: kind
        )
      end

      # End a span, optionally setting additional attributes and error state.
      #
      # @param span [Span] the span to end
      # @param attributes [Hash] additional attributes to set
      # @param error [Exception, nil] exception if the operation failed
      # @return [void]
      def end_span(span, attributes: {}, error: nil)
        return unless span&.recording?

        span.set_attributes(attributes) unless attributes.empty?

        if error
          span.set_status(:error, error.message)
          span.record_exception(error)
        else
          span.set_status(:ok)
        end

        span.finish
      end

      # Start a span for a model invocation.
      #
      # @param model_id [String] the model identifier
      # @param parent [Span, nil] optional parent span
      # @param attributes [Hash] additional attributes
      # @return [Span]
      def start_model_span(model_id, parent: nil, attributes: {})
        start_span(
          "chat",
          parent: parent,
          attributes: attributes.merge(
            "gen_ai.operation.name" => "chat",
            "gen_ai.request.model" => model_id
          )
        )
      end

      # Start a span for a tool call.
      #
      # @param tool_name [String] the tool name
      # @param tool_use_id [String] the tool use identifier
      # @param parent [Span, nil] optional parent span
      # @param attributes [Hash] additional attributes
      # @return [Span]
      def start_tool_span(tool_name, tool_use_id:, parent: nil, attributes: {})
        start_span(
          "execute_tool #{tool_name}",
          parent: parent,
          attributes: attributes.merge(
            "gen_ai.operation.name" => "execute_tool",
            "gen_ai.tool.name" => tool_name,
            "gen_ai.tool.call.id" => tool_use_id
          )
        )
      end

      # Start a span for an event loop cycle.
      #
      # @param cycle_id [String] the cycle identifier
      # @param parent [Span, nil] optional parent span
      # @param attributes [Hash] additional attributes
      # @return [Span]
      def start_cycle_span(cycle_id, parent: nil, attributes: {})
        start_span(
          "execute_event_loop_cycle",
          parent: parent,
          attributes: attributes.merge(
            "gen_ai.operation.name" => "execute_event_loop_cycle",
            "event_loop.cycle_id" => cycle_id
          )
        )
      end

      # Start a span for an agent invocation.
      #
      # @param agent_name [String] the agent name
      # @param model_id [String, nil] the model identifier
      # @param parent [Span, nil] optional parent span
      # @param attributes [Hash] additional attributes
      # @return [Span]
      def start_agent_span(agent_name, model_id: nil, parent: nil, attributes: {})
        attrs = attributes.merge(
          "gen_ai.operation.name" => "invoke_agent",
          "gen_ai.agent.name" => agent_name
        )
        attrs["gen_ai.request.model"] = model_id if model_id

        start_span("invoke_agent #{agent_name}", parent: parent, attributes: attrs)
      end
    end

    # Represents a single span in a trace.
    #
    # Provides an API compatible with OpenTelemetry spans but backed by
    # simple Ruby data structures. Can be extended to forward to a real
    # OTel span when the SDK is available.
    class Span
      # @return [String] the span identifier
      attr_reader :span_id

      # @return [String] the trace identifier
      attr_reader :trace_id

      # @return [String] the span name
      attr_reader :name

      # @return [Span, nil] the parent span
      attr_reader :parent

      # @return [Symbol] the span kind
      attr_reader :kind

      # @return [Hash] span attributes
      attr_reader :attributes

      # @return [Array<Hash>] recorded events
      attr_reader :events

      # @return [Time] when the span started
      attr_reader :start_time

      # @return [Time, nil] when the span ended
      attr_reader :end_time

      # @return [Symbol, nil] span status (:ok, :error, :unset)
      attr_reader :status

      # @return [String, nil] status description
      attr_reader :status_description

      # @param name [String] the span name
      # @param parent [Span, nil] optional parent span
      # @param attributes [Hash] initial attributes
      # @param kind [Symbol] span kind
      def initialize(name:, parent: nil, attributes: {}, kind: :internal)
        @span_id = SecureRandom.hex(8)
        @trace_id = parent&.trace_id || SecureRandom.hex(16)
        @name = name
        @parent = parent
        @kind = kind
        @attributes = attributes.dup
        @events = []
        @start_time = Time.now
        @end_time = nil
        @status = :unset
        @status_description = nil
        @recording = true
      end

      # Whether the span is still recording.
      #
      # @return [Boolean]
      def recording?
        @recording
      end

      # Set a single attribute.
      #
      # @param key [String] attribute key
      # @param value [Object] attribute value
      # @return [void]
      def set_attribute(key, value)
        @attributes[key] = value if @recording
      end

      # Set multiple attributes.
      #
      # @param attrs [Hash] attributes to set
      # @return [void]
      def set_attributes(attrs)
        @attributes.merge!(attrs) if @recording
      end

      # Set the span status.
      #
      # @param code [Symbol] :ok, :error, or :unset
      # @param description [String, nil] optional description
      # @return [void]
      def set_status(code, description = nil)
        return unless @recording

        @status = code
        @status_description = description
      end

      # Add an event to the span.
      #
      # @param name [String] event name
      # @param attributes [Hash] event attributes
      # @return [void]
      def add_event(name, attributes: {})
        return unless @recording

        @events << {
          name: name,
          timestamp: Time.now,
          attributes: attributes
        }
      end

      # Record an exception as a span event.
      #
      # @param exception [Exception] the exception to record
      # @return [void]
      def record_exception(exception)
        add_event("exception", attributes: {
          "exception.type" => exception.class.name,
          "exception.message" => exception.message,
          "exception.stacktrace" => exception.backtrace&.first(10)&.join("\n")
        })
      end

      # End the span (stop recording).
      #
      # @return [void]
      def finish
        return unless @recording

        @end_time = Time.now
        @recording = false
      end

      # Duration of the span in seconds.
      #
      # @return [Float, nil] duration or nil if not finished
      def duration
        return nil unless @end_time

        @end_time - @start_time
      end

      # Parent span ID, or nil if root.
      #
      # @return [String, nil]
      def parent_span_id
        @parent&.span_id
      end

      # Convert to a hash representation suitable for serialization.
      #
      # @return [Hash]
      def to_h
        {
          span_id: @span_id,
          trace_id: @trace_id,
          parent_span_id: parent_span_id,
          name: @name,
          kind: @kind,
          attributes: @attributes,
          events: @events,
          start_time: @start_time.iso8601(6),
          end_time: @end_time&.iso8601(6),
          status: @status,
          status_description: @status_description,
          duration: duration
        }
      end
    end

    # Module-level access to a shared tracer instance.
    class << self
      # Get or create the global tracer instance.
      #
      # @return [Tracer]
      def tracer
        @tracer ||= Tracer.new
      end

      # Reset the global tracer (useful for testing).
      #
      # @return [void]
      def reset_tracer!
        @tracer = nil
      end
    end
  end
end
