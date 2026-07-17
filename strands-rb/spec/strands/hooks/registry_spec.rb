# frozen_string_literal: true

require "spec_helper"

RSpec.describe Strands::Hooks::Registry do
  subject(:registry) { described_class.new }

  let(:agent) { double("agent") }

  describe "#add_callback" do
    it "registers a callback for an event class" do
      registry.add_callback(Strands::Hooks::BeforeModelCallEvent) { |_e| }

      expect(registry.callback_count(Strands::Hooks::BeforeModelCallEvent)).to eq(1)
    end

    it "raises if no block is given" do
      expect {
        registry.add_callback(Strands::Hooks::BeforeModelCallEvent)
      }.to raise_error(ArgumentError, /block is required/)
    end

    it "raises if event_class is not a Class" do
      expect {
        registry.add_callback("not a class") { |_e| }
      }.to raise_error(ArgumentError, /must be a Class/)
    end

    it "registers multiple callbacks for the same event type" do
      registry.add_callback(Strands::Hooks::BeforeModelCallEvent) { |_e| }
      registry.add_callback(Strands::Hooks::BeforeModelCallEvent) { |_e| }

      expect(registry.callback_count(Strands::Hooks::BeforeModelCallEvent)).to eq(2)
    end
  end

  describe "#fire" do
    it "invokes callbacks for the correct event type" do
      results = []
      registry.add_callback(Strands::Hooks::BeforeModelCallEvent) { |_e| results << "model" }
      registry.add_callback(Strands::Hooks::BeforeToolCallEvent) { |_e| results << "tool" }

      event = Strands::Hooks::BeforeModelCallEvent.new(agent: agent)
      registry.fire(event)

      expect(results).to eq(["model"])
    end

    it "invokes callbacks in order of priority" do
      results = []
      registry.add_callback(Strands::Hooks::BeforeModelCallEvent, order: Strands::Hooks::HookOrder::AFTER) { |_e| results << "after" }
      registry.add_callback(Strands::Hooks::BeforeModelCallEvent, order: Strands::Hooks::HookOrder::BEFORE) { |_e| results << "before" }
      registry.add_callback(Strands::Hooks::BeforeModelCallEvent, order: Strands::Hooks::HookOrder::NORMAL) { |_e| results << "normal" }

      event = Strands::Hooks::BeforeModelCallEvent.new(agent: agent)
      registry.fire(event)

      expect(results).to eq(%w[before normal after])
    end

    it "preserves registration order within the same priority" do
      results = []
      registry.add_callback(Strands::Hooks::BeforeModelCallEvent) { |_e| results << "first" }
      registry.add_callback(Strands::Hooks::BeforeModelCallEvent) { |_e| results << "second" }
      registry.add_callback(Strands::Hooks::BeforeModelCallEvent) { |_e| results << "third" }

      event = Strands::Hooks::BeforeModelCallEvent.new(agent: agent)
      registry.fire(event)

      expect(results).to eq(%w[first second third])
    end

    it "reverses callbacks within same priority for reverse-ordered events" do
      results = []
      registry.add_callback(Strands::Hooks::AfterModelCallEvent) { |_e| results << "first" }
      registry.add_callback(Strands::Hooks::AfterModelCallEvent) { |_e| results << "second" }
      registry.add_callback(Strands::Hooks::AfterModelCallEvent) { |_e| results << "third" }

      event = Strands::Hooks::AfterModelCallEvent.new(agent: agent)
      registry.fire(event)

      expect(results).to eq(%w[third second first])
    end

    it "respects priority ordering even for reverse-ordered events" do
      results = []
      registry.add_callback(Strands::Hooks::AfterModelCallEvent, order: 10) { |_e| results << "high" }
      registry.add_callback(Strands::Hooks::AfterModelCallEvent, order: -10) { |_e| results << "low_first" }
      registry.add_callback(Strands::Hooks::AfterModelCallEvent, order: -10) { |_e| results << "low_second" }

      event = Strands::Hooks::AfterModelCallEvent.new(agent: agent)
      registry.fire(event)

      # Priority order still: -10 comes before 10
      # Within -10 group: reversed -> low_second, low_first
      # Within 10 group: reversed -> high (only one)
      expect(results).to eq(%w[low_second low_first high])
    end

    it "passes the event to callbacks" do
      received_event = nil
      registry.add_callback(Strands::Hooks::BeforeModelCallEvent) { |e| received_event = e }

      event = Strands::Hooks::BeforeModelCallEvent.new(agent: agent)
      registry.fire(event)

      expect(received_event).to eq(event)
    end

    it "does nothing if no callbacks are registered for event type" do
      event = Strands::Hooks::BeforeModelCallEvent.new(agent: agent)
      expect { registry.fire(event) }.not_to raise_error
    end
  end

  describe "#add_hook" do
    it "registers callbacks from a provider" do
      provider = double("provider")
      allow(provider).to receive(:register_hooks) do |reg|
        reg.add_callback(Strands::Hooks::BeforeModelCallEvent) { |_e| }
      end

      registry.add_hook(provider)
      expect(registry.callback_count(Strands::Hooks::BeforeModelCallEvent)).to eq(1)
    end

    it "raises if provider does not respond to register_hooks" do
      expect {
        registry.add_hook(Object.new)
      }.to raise_error(ArgumentError, /respond to #register_hooks/)
    end
  end

  describe "#callbacks?" do
    it "returns false when empty" do
      expect(registry.callbacks?).to be false
    end

    it "returns true when callbacks are registered" do
      registry.add_callback(Strands::Hooks::BeforeModelCallEvent) { |_e| }
      expect(registry.callbacks?).to be true
    end
  end

  describe "#callbacks_for" do
    it "returns callbacks for a specific event type" do
      cb1 = proc { |_e| }
      cb2 = proc { |_e| }
      registry.add_callback(Strands::Hooks::BeforeModelCallEvent, &cb1)
      registry.add_callback(Strands::Hooks::BeforeModelCallEvent, &cb2)

      callbacks = registry.callbacks_for(Strands::Hooks::BeforeModelCallEvent)
      expect(callbacks).to eq([cb1, cb2])
    end

    it "returns empty array for unregistered event types" do
      expect(registry.callbacks_for(Strands::Hooks::AfterModelCallEvent)).to eq([])
    end
  end
end
