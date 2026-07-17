# frozen_string_literal: true

require "spec_helper"

RSpec.describe Strands::Telemetry::Metrics do
  subject(:metrics) { described_class.new }

  describe "#record_usage" do
    it "accumulates token counts" do
      metrics.start_invocation
      metrics.record_usage(input_tokens: 100, output_tokens: 50)
      metrics.record_usage(input_tokens: 200, output_tokens: 80)

      expect(metrics.total_input_tokens).to eq(300)
      expect(metrics.total_output_tokens).to eq(130)
      expect(metrics.total_tokens).to eq(430)
    end

    it "tracks model call count" do
      metrics.start_invocation
      metrics.record_usage(input_tokens: 10, output_tokens: 5)
      metrics.record_usage(input_tokens: 20, output_tokens: 10)

      expect(metrics.model_call_count).to eq(2)
    end

    it "tracks per-invocation usage" do
      metrics.start_invocation
      metrics.record_usage(input_tokens: 100, output_tokens: 50)

      metrics.start_invocation
      metrics.record_usage(input_tokens: 200, output_tokens: 80)

      expect(metrics.invocations.size).to eq(2)
      expect(metrics.invocations[0].input_tokens).to eq(100)
      expect(metrics.invocations[1].input_tokens).to eq(200)
    end

    it "tracks cache tokens" do
      metrics.start_invocation
      metrics.record_usage(
        input_tokens: 100,
        output_tokens: 50,
        cache_read_tokens: 30,
        cache_write_tokens: 20
      )

      invocation = metrics.invocations.first
      expect(invocation.cache_read_tokens).to eq(30)
      expect(invocation.cache_write_tokens).to eq(20)
    end
  end

  describe "#record_latency" do
    it "accumulates latency" do
      metrics.start_invocation
      metrics.record_latency(100.5)
      metrics.record_latency(50.2)

      expect(metrics.total_latency_ms).to be_within(0.01).of(150.7)
    end
  end

  describe "#record_tool_call" do
    it "tracks tool call metrics" do
      metrics.record_tool_call("calculator", duration: 0.5, success: true)
      metrics.record_tool_call("calculator", duration: 0.3, success: true)
      metrics.record_tool_call("calculator", duration: 1.0, success: false)

      tool = metrics.tool_metrics["calculator"]
      expect(tool.call_count).to eq(3)
      expect(tool.success_count).to eq(2)
      expect(tool.error_count).to eq(1)
      expect(tool.total_duration).to be_within(0.01).of(1.8)
    end

    it "calculates average duration" do
      metrics.record_tool_call("search", duration: 1.0, success: true)
      metrics.record_tool_call("search", duration: 3.0, success: true)

      expect(metrics.tool_metrics["search"].average_duration).to eq(2.0)
    end

    it "calculates success rate" do
      metrics.record_tool_call("api", duration: 0.1, success: true)
      metrics.record_tool_call("api", duration: 0.2, success: false)

      expect(metrics.tool_metrics["api"].success_rate).to eq(0.5)
    end
  end

  describe "#record_cycle" do
    it "tracks cycle count" do
      metrics.start_invocation
      metrics.record_cycle(duration: 2.5)
      metrics.record_cycle(duration: 1.5)

      expect(metrics.cycle_count).to eq(2)
    end

    it "tracks per-invocation cycles" do
      metrics.start_invocation
      metrics.record_cycle(duration: 2.5)
      metrics.record_cycle(duration: 1.5)

      expect(metrics.invocations.first.cycle_count).to eq(2)
      expect(metrics.invocations.first.cycle_durations).to eq([2.5, 1.5])
    end
  end

  describe "#summary" do
    it "returns a comprehensive hash" do
      metrics.start_invocation
      metrics.record_usage(input_tokens: 100, output_tokens: 50)
      metrics.record_latency(150.0)
      metrics.record_tool_call("calc", duration: 0.5, success: true)
      metrics.record_cycle(duration: 2.0)

      summary = metrics.summary
      expect(summary[:total_input_tokens]).to eq(100)
      expect(summary[:total_output_tokens]).to eq(50)
      expect(summary[:total_tokens]).to eq(150)
      expect(summary[:total_latency_ms]).to eq(150.0)
      expect(summary[:model_call_count]).to eq(1)
      expect(summary[:cycle_count]).to eq(1)
      expect(summary[:tool_metrics]).to have_key("calc")
      expect(summary[:invocations].size).to eq(1)
    end
  end

  describe "#reset!" do
    it "resets all metrics to initial state" do
      metrics.start_invocation
      metrics.record_usage(input_tokens: 100, output_tokens: 50)
      metrics.record_tool_call("calc", duration: 0.5, success: true)
      metrics.reset!

      expect(metrics.total_input_tokens).to eq(0)
      expect(metrics.total_output_tokens).to eq(0)
      expect(metrics.tool_metrics).to be_empty
      expect(metrics.invocations).to be_empty
    end
  end
end

RSpec.describe Strands::Telemetry::Tracer do
  subject(:tracer) { described_class.new }

  describe "#start_span" do
    it "creates a span with name and attributes" do
      span = tracer.start_span("test_operation", attributes: { "key" => "value" })
      expect(span).to be_a(Strands::Telemetry::Span)
      expect(span.name).to eq("test_operation")
      expect(span.attributes["key"]).to eq("value")
    end

    it "includes service name in attributes" do
      span = tracer.start_span("op")
      expect(span.attributes["gen_ai.system"]).to eq("strands-agents")
    end

    it "links to parent span" do
      parent = tracer.start_span("parent")
      child = tracer.start_span("child", parent: parent)
      expect(child.parent_span_id).to eq(parent.span_id)
      expect(child.trace_id).to eq(parent.trace_id)
    end
  end

  describe "#end_span" do
    it "ends the span successfully" do
      span = tracer.start_span("op")
      tracer.end_span(span)
      expect(span.recording?).to be false
      expect(span.status).to eq(:ok)
    end

    it "records error on span" do
      span = tracer.start_span("op")
      error = RuntimeError.new("something went wrong")
      tracer.end_span(span, error: error)
      expect(span.status).to eq(:error)
      expect(span.status_description).to eq("something went wrong")
    end
  end

  describe "#start_model_span" do
    it "creates a span with model attributes" do
      span = tracer.start_model_span("claude-3")
      expect(span.attributes["gen_ai.request.model"]).to eq("claude-3")
      expect(span.attributes["gen_ai.operation.name"]).to eq("chat")
    end
  end

  describe "#start_tool_span" do
    it "creates a span with tool attributes" do
      span = tracer.start_tool_span("calculator", tool_use_id: "tool_123")
      expect(span.attributes["gen_ai.tool.name"]).to eq("calculator")
      expect(span.attributes["gen_ai.tool.call.id"]).to eq("tool_123")
    end
  end

  describe "#start_agent_span" do
    it "creates a span with agent attributes" do
      span = tracer.start_agent_span("my-agent", model_id: "claude-3")
      expect(span.attributes["gen_ai.agent.name"]).to eq("my-agent")
      expect(span.attributes["gen_ai.request.model"]).to eq("claude-3")
    end
  end
end

RSpec.describe Strands::Telemetry::Span do
  subject(:span) do
    described_class.new(name: "test", attributes: { "initial" => true })
  end

  describe "#recording?" do
    it "returns true while recording" do
      expect(span.recording?).to be true
    end

    it "returns false after finish" do
      span.finish
      expect(span.recording?).to be false
    end
  end

  describe "#set_attribute" do
    it "adds an attribute" do
      span.set_attribute("key", "value")
      expect(span.attributes["key"]).to eq("value")
    end

    it "does not add after finish" do
      span.finish
      span.set_attribute("late", "value")
      expect(span.attributes).not_to have_key("late")
    end
  end

  describe "#add_event" do
    it "records events" do
      span.add_event("my.event", attributes: { "detail" => "info" })
      expect(span.events.size).to eq(1)
      expect(span.events.first[:name]).to eq("my.event")
    end
  end

  describe "#record_exception" do
    it "records an exception event" do
      error = RuntimeError.new("oops")
      span.record_exception(error)
      event = span.events.first
      expect(event[:name]).to eq("exception")
      expect(event[:attributes]["exception.type"]).to eq("RuntimeError")
      expect(event[:attributes]["exception.message"]).to eq("oops")
    end
  end

  describe "#duration" do
    it "returns nil before finish" do
      expect(span.duration).to be_nil
    end

    it "returns duration after finish" do
      sleep(0.01)
      span.finish
      expect(span.duration).to be > 0
    end
  end

  describe "#to_h" do
    it "serializes the span" do
      span.finish
      hash = span.to_h
      expect(hash[:name]).to eq("test")
      expect(hash[:span_id]).not_to be_nil
      expect(hash[:trace_id]).not_to be_nil
      expect(hash[:status]).to eq(:unset)
    end
  end
end
