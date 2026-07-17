# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Strands::Hooks event classes" do
  let(:agent) { double("agent") }

  describe Strands::Hooks::Event do
    it "has reverse_callbacks? returning false by default" do
      event = Strands::Hooks::Event.new
      expect(event.reverse_callbacks?).to be false
    end
  end

  describe Strands::Hooks::AgentEvent do
    it "stores the agent" do
      event = Strands::Hooks::AgentEvent.new(agent: agent)
      expect(event.agent).to eq(agent)
    end
  end

  describe Strands::Hooks::AgentInitializedEvent do
    it "is an AgentEvent" do
      event = Strands::Hooks::AgentInitializedEvent.new(agent: agent)
      expect(event).to be_a(Strands::Hooks::AgentEvent)
      expect(event.agent).to eq(agent)
    end
  end

  describe Strands::Hooks::BeforeInvocationEvent do
    it "stores agent, invocation_state, and messages" do
      event = Strands::Hooks::BeforeInvocationEvent.new(
        agent: agent,
        invocation_state: { key: "value" },
        messages: [{ role: "user" }]
      )

      expect(event.agent).to eq(agent)
      expect(event.invocation_state).to eq({ key: "value" })
      expect(event.messages).to eq([{ role: "user" }])
      expect(event.cancel).to be false
    end

    it "allows modifying cancel and messages" do
      event = Strands::Hooks::BeforeInvocationEvent.new(agent: agent)
      event.cancel = "cancelled"
      event.messages = [{ role: "assistant" }]

      expect(event.cancel).to eq("cancelled")
      expect(event.messages).to eq([{ role: "assistant" }])
    end

    it "does not reverse callbacks" do
      event = Strands::Hooks::BeforeInvocationEvent.new(agent: agent)
      expect(event.reverse_callbacks?).to be false
    end
  end

  describe Strands::Hooks::AfterInvocationEvent do
    it "stores agent, invocation_state, and result" do
      event = Strands::Hooks::AfterInvocationEvent.new(
        agent: agent,
        invocation_state: { key: "value" },
        result: "done"
      )

      expect(event.agent).to eq(agent)
      expect(event.invocation_state).to eq({ key: "value" })
      expect(event.result).to eq("done")
      expect(event.resume).to be_nil
    end

    it "allows setting resume" do
      event = Strands::Hooks::AfterInvocationEvent.new(agent: agent)
      event.resume = "continue"
      expect(event.resume).to eq("continue")
    end

    it "reverses callbacks" do
      event = Strands::Hooks::AfterInvocationEvent.new(agent: agent)
      expect(event.reverse_callbacks?).to be true
    end
  end

  describe Strands::Hooks::MessageAddedEvent do
    it "stores agent and message" do
      msg = { role: "user", content: "hello" }
      event = Strands::Hooks::MessageAddedEvent.new(agent: agent, message: msg)

      expect(event.agent).to eq(agent)
      expect(event.message).to eq(msg)
    end
  end

  describe Strands::Hooks::BeforeToolCallEvent do
    it "stores agent, selected_tool, tool_use, and invocation_state" do
      tool = double("tool")
      tool_use = { name: "calc", input: {} }
      event = Strands::Hooks::BeforeToolCallEvent.new(
        agent: agent,
        selected_tool: tool,
        tool_use: tool_use,
        invocation_state: { run: 1 }
      )

      expect(event.agent).to eq(agent)
      expect(event.selected_tool).to eq(tool)
      expect(event.tool_use).to eq(tool_use)
      expect(event.invocation_state).to eq({ run: 1 })
      expect(event.cancel_tool).to be false
    end

    it "allows modifying cancel_tool and selected_tool" do
      event = Strands::Hooks::BeforeToolCallEvent.new(
        agent: agent, selected_tool: nil, tool_use: {}
      )
      event.cancel_tool = "not allowed"
      event.selected_tool = double("new_tool")

      expect(event.cancel_tool).to eq("not allowed")
      expect(event.selected_tool).not_to be_nil
    end
  end

  describe Strands::Hooks::AfterToolCallEvent do
    it "stores agent, selected_tool, tool_use, result, and exception" do
      tool = double("tool")
      error = RuntimeError.new("oops")
      event = Strands::Hooks::AfterToolCallEvent.new(
        agent: agent,
        selected_tool: tool,
        tool_use: { name: "calc" },
        invocation_state: {},
        result: "42",
        exception: error
      )

      expect(event.agent).to eq(agent)
      expect(event.selected_tool).to eq(tool)
      expect(event.result).to eq("42")
      expect(event.exception).to eq(error)
      expect(event.retry).to be false
    end

    it "allows modifying result and retry" do
      event = Strands::Hooks::AfterToolCallEvent.new(
        agent: agent, selected_tool: nil, tool_use: {}
      )
      event.result = "new_result"
      event.retry = true

      expect(event.result).to eq("new_result")
      expect(event.retry).to be true
    end

    it "reverses callbacks" do
      event = Strands::Hooks::AfterToolCallEvent.new(
        agent: agent, selected_tool: nil, tool_use: {}
      )
      expect(event.reverse_callbacks?).to be true
    end
  end

  describe Strands::Hooks::BeforeModelCallEvent do
    it "stores agent and invocation_state" do
      event = Strands::Hooks::BeforeModelCallEvent.new(
        agent: agent,
        invocation_state: { token_budget: 1000 }
      )

      expect(event.agent).to eq(agent)
      expect(event.invocation_state).to eq({ token_budget: 1000 })
      expect(event.cancel).to be false
    end

    it "allows modifying cancel" do
      event = Strands::Hooks::BeforeModelCallEvent.new(agent: agent)
      event.cancel = "stop"
      expect(event.cancel).to eq("stop")
    end
  end

  describe Strands::Hooks::AfterModelCallEvent do
    it "stores agent, invocation_state, stop_reason, message, and exception" do
      event = Strands::Hooks::AfterModelCallEvent.new(
        agent: agent,
        invocation_state: {},
        stop_reason: "end_turn",
        message: { role: "assistant", content: "hi" },
        exception: nil
      )

      expect(event.agent).to eq(agent)
      expect(event.stop_reason).to eq("end_turn")
      expect(event.message).to eq({ role: "assistant", content: "hi" })
      expect(event.exception).to be_nil
      expect(event.retry).to be false
    end

    it "allows modifying retry" do
      event = Strands::Hooks::AfterModelCallEvent.new(agent: agent)
      event.retry = true
      expect(event.retry).to be true
    end

    it "reverses callbacks" do
      event = Strands::Hooks::AfterModelCallEvent.new(agent: agent)
      expect(event.reverse_callbacks?).to be true
    end
  end
end
