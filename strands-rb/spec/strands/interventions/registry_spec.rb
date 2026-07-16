# frozen_string_literal: true

require "spec_helper"

RSpec.describe Strands::Interventions::Registry do
  let(:agent) { double("agent") }
  let(:hook_registry) { Strands::Hooks::Registry.new }

  describe "initialization" do
    it "raises on duplicate handler names" do
      handler1 = instance_double(Strands::Interventions::Handler, name: "same-name")
      handler2 = instance_double(Strands::Interventions::Handler, name: "same-name")
      allow(handler1).to receive(:class).and_return(Class.new(Strands::Interventions::Handler))
      allow(handler2).to receive(:class).and_return(Class.new(Strands::Interventions::Handler))

      expect {
        described_class.new(handlers: [handler1, handler2], hook_registry: hook_registry)
      }.to raise_error(ArgumentError, /Duplicate intervention handler name/)
    end

    it "exposes handlers" do
      handler = Class.new(Strands::Interventions::Handler) do
        def name
          "test"
        end
      end.new

      registry = described_class.new(handlers: [handler], hook_registry: hook_registry)
      expect(registry.handlers).to eq([handler])
    end
  end

  describe "Deny short-circuiting" do
    it "short-circuits on Deny for before_tool_call" do
      deny_handler = Class.new(Strands::Interventions::Handler) do
        def name
          "deny-handler"
        end

        def before_tool_call(event)
          Strands::Interventions::Deny.new(reason: "not allowed")
        end
      end.new

      proceed_handler = Class.new(Strands::Interventions::Handler) do
        def name
          "proceed-handler"
        end

        def before_tool_call(event)
          Strands::Interventions::Proceed.new
        end
      end.new

      described_class.new(handlers: [deny_handler, proceed_handler], hook_registry: hook_registry)

      event = Strands::Hooks::BeforeToolCallEvent.new(
        agent: agent, selected_tool: nil, tool_use: { name: "test" }
      )
      hook_registry.fire(event)

      expect(event.cancel_tool).to eq("DENIED: not allowed")
    end

    it "short-circuits on Deny for before_invocation" do
      deny_handler = Class.new(Strands::Interventions::Handler) do
        def name
          "deny-invocation"
        end

        def before_invocation(event)
          Strands::Interventions::Deny.new(reason: "stop")
        end
      end.new

      described_class.new(handlers: [deny_handler], hook_registry: hook_registry)

      event = Strands::Hooks::BeforeInvocationEvent.new(agent: agent)
      hook_registry.fire(event)

      expect(event.cancel).to eq("DENIED: stop")
    end

    it "short-circuits on Deny for before_model_call" do
      deny_handler = Class.new(Strands::Interventions::Handler) do
        def name
          "deny-model"
        end

        def before_model_call(event)
          Strands::Interventions::Deny.new(reason: "no model")
        end
      end.new

      described_class.new(handlers: [deny_handler], hook_registry: hook_registry)

      event = Strands::Hooks::BeforeModelCallEvent.new(agent: agent)
      hook_registry.fire(event)

      expect(event.cancel).to eq("DENIED: no model")
    end
  end

  describe "handler ordering" do
    it "evaluates handlers in registration order" do
      call_order = []

      handler1 = Class.new(Strands::Interventions::Handler) do
        define_method(:name) { "handler-1" }
        define_method(:before_tool_call) do |event|
          call_order << "handler-1"
          Strands::Interventions::Proceed.new
        end
      end.new

      handler2 = Class.new(Strands::Interventions::Handler) do
        define_method(:name) { "handler-2" }
        define_method(:before_tool_call) do |event|
          call_order << "handler-2"
          Strands::Interventions::Proceed.new
        end
      end.new

      described_class.new(handlers: [handler1, handler2], hook_registry: hook_registry)

      event = Strands::Hooks::BeforeToolCallEvent.new(
        agent: agent, selected_tool: nil, tool_use: {}
      )
      hook_registry.fire(event)

      expect(call_order).to eq(%w[handler-1 handler-2])
    end

    it "skips handlers after a Deny" do
      call_order = []

      handler1 = Class.new(Strands::Interventions::Handler) do
        define_method(:name) { "deny-first" }
        define_method(:before_tool_call) do |event|
          call_order << "deny-first"
          Strands::Interventions::Deny.new(reason: "blocked")
        end
      end.new

      handler2 = Class.new(Strands::Interventions::Handler) do
        define_method(:name) { "never-called" }
        define_method(:before_tool_call) do |event|
          call_order << "never-called"
          Strands::Interventions::Proceed.new
        end
      end.new

      described_class.new(handlers: [handler1, handler2], hook_registry: hook_registry)

      event = Strands::Hooks::BeforeToolCallEvent.new(
        agent: agent, selected_tool: nil, tool_use: {}
      )
      hook_registry.fire(event)

      expect(call_order).to eq(["deny-first"])
    end
  end

  describe "Guide accumulation" do
    it "accumulates multiple Guide actions" do
      handler1 = Class.new(Strands::Interventions::Handler) do
        define_method(:name) { "guide-1" }
        define_method(:before_invocation) do |event|
          Strands::Interventions::Guide.new(feedback: "tip 1")
        end
      end.new

      handler2 = Class.new(Strands::Interventions::Handler) do
        define_method(:name) { "guide-2" }
        define_method(:before_invocation) do |event|
          Strands::Interventions::Guide.new(feedback: "tip 2")
        end
      end.new

      described_class.new(handlers: [handler1, handler2], hook_registry: hook_registry)

      event = Strands::Hooks::BeforeInvocationEvent.new(agent: agent)
      hook_registry.fire(event)

      expect(event.cancel).to include("[guide-1] tip 1")
      expect(event.cancel).to include("[guide-2] tip 2")
    end
  end

  describe "Transform action" do
    it "applies transformation to events" do
      handler = Class.new(Strands::Interventions::Handler) do
        define_method(:name) { "transform-handler" }
        define_method(:before_tool_call) do |event|
          Strands::Interventions::Transform.new(
            apply: ->(e) { e.tool_use = { name: "transformed" } }
          )
        end
      end.new

      described_class.new(handlers: [handler], hook_registry: hook_registry)

      event = Strands::Hooks::BeforeToolCallEvent.new(
        agent: agent, selected_tool: nil, tool_use: { name: "original" }
      )
      hook_registry.fire(event)

      expect(event.tool_use).to eq({ name: "transformed" })
    end

    it "applies transformation for after_tool_call" do
      handler = Class.new(Strands::Interventions::Handler) do
        define_method(:name) { "after-transform" }
        define_method(:after_tool_call) do |event|
          Strands::Interventions::Transform.new(
            apply: ->(e) { e.result = "modified" }
          )
        end
      end.new

      described_class.new(handlers: [handler], hook_registry: hook_registry)

      event = Strands::Hooks::AfterToolCallEvent.new(
        agent: agent, selected_tool: nil, tool_use: {}, result: "original"
      )
      hook_registry.fire(event)

      expect(event.result).to eq("modified")
    end
  end

  describe "after_model_call Guide triggers retry" do
    it "sets retry on Guide for after_model_call" do
      handler = Class.new(Strands::Interventions::Handler) do
        define_method(:name) { "retry-handler" }
        define_method(:after_model_call) do |event|
          Strands::Interventions::Guide.new(feedback: "try again")
        end
      end.new

      described_class.new(handlers: [handler], hook_registry: hook_registry)

      event = Strands::Hooks::AfterModelCallEvent.new(agent: agent)
      hook_registry.fire(event)

      expect(event.retry).to be true
    end
  end

  describe "error handling" do
    it "re-raises errors when on_error is :throw" do
      handler = Class.new(Strands::Interventions::Handler) do
        define_method(:name) { "throwing" }
        define_method(:before_tool_call) do |event|
          raise "something broke"
        end
      end.new

      described_class.new(handlers: [handler], hook_registry: hook_registry)

      event = Strands::Hooks::BeforeToolCallEvent.new(
        agent: agent, selected_tool: nil, tool_use: {}
      )

      expect { hook_registry.fire(event) }.to raise_error(RuntimeError, "something broke")
    end

    it "converts to Deny when on_error is :deny" do
      handler = Class.new(Strands::Interventions::Handler) do
        define_method(:name) { "deny-on-error" }
        define_method(:on_error) { :deny }
        define_method(:before_tool_call) do |event|
          raise "broken"
        end
      end.new

      described_class.new(handlers: [handler], hook_registry: hook_registry)

      event = Strands::Hooks::BeforeToolCallEvent.new(
        agent: agent, selected_tool: nil, tool_use: {}
      )
      hook_registry.fire(event)

      expect(event.cancel_tool).to eq("DENIED: Handler threw: broken")
    end

    it "skips handler when on_error is :proceed" do
      handler = Class.new(Strands::Interventions::Handler) do
        define_method(:name) { "proceed-on-error" }
        define_method(:on_error) { :proceed }
        define_method(:before_tool_call) do |event|
          raise "ignored"
        end
      end.new

      described_class.new(handlers: [handler], hook_registry: hook_registry)

      event = Strands::Hooks::BeforeToolCallEvent.new(
        agent: agent, selected_tool: nil, tool_use: {}
      )
      hook_registry.fire(event)

      expect(event.cancel_tool).to be false
    end
  end

  describe "only overridden methods are hooked" do
    it "does not register hooks for non-overridden methods" do
      handler = Class.new(Strands::Interventions::Handler) do
        define_method(:name) { "partial" }
        define_method(:before_tool_call) do |event|
          Strands::Interventions::Deny.new(reason: "denied")
        end
      end.new

      described_class.new(handlers: [handler], hook_registry: hook_registry)

      # before_model_call is not overridden, so no hook should be registered for it
      expect(hook_registry.callback_count(Strands::Hooks::BeforeModelCallEvent)).to eq(0)
      expect(hook_registry.callback_count(Strands::Hooks::BeforeToolCallEvent)).to eq(1)
    end
  end
end
