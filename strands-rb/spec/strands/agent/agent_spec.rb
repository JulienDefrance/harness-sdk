# frozen_string_literal: true

require "spec_helper"

RSpec.describe Strands::Agent::Agent do
  # Reusable mock model
  let(:mock_model) do
    model = Object.new

    def model.stream(messages, system_prompt: nil, tools: nil, tool_choice: nil, **kwargs, &block)
      block.call(Strands::Types::Streaming::StreamEvent.new(
                   message_start: Strands::Types::Streaming::MessageStartEvent.new(role: :assistant)
                 ))
      block.call(Strands::Types::Streaming::StreamEvent.new(
                   content_block_delta: Strands::Types::Streaming::ContentBlockDeltaEvent.new(
                     content_block_index: 0,
                     delta: Strands::Types::Streaming::ContentBlockDelta.new(text: "Test response")
                   )
                 ))
      block.call(Strands::Types::Streaming::StreamEvent.new(
                   content_block_stop: Strands::Types::Streaming::ContentBlockStopEvent.new(content_block_index: 0)
                 ))
      block.call(Strands::Types::Streaming::StreamEvent.new(
                   message_stop: Strands::Types::Streaming::MessageStopEvent.new(stop_reason: :end_turn)
                 ))
    end

    def model.update_config(**opts); end

    def model.get_config
      {}
    end

    model
  end

  describe "#initialize" do
    it "creates an agent with default configuration" do
      agent = described_class.new(model: mock_model)
      expect(agent.model).to eq(mock_model)
      expect(agent.messages).to eq([])
      expect(agent.name).to eq("Strands Agent")
      expect(agent.system_prompt).to be_nil
    end

    it "accepts all configuration options" do
      agent = described_class.new(
        model: mock_model,
        system_prompt: "Be helpful",
        name: "TestBot",
        max_turns: 10
      )
      expect(agent.system_prompt).to eq("Be helpful")
      expect(agent.name).to eq("TestBot")
      expect(agent.max_turns).to eq(10)
    end

    it "fires AgentInitializedEvent" do
      initialized = false
      hook_provider = Object.new
      hook_provider.define_singleton_method(:register_hooks) do |registry|
        registry.add_callback(Strands::Hooks::AgentInitializedEvent) do |_event|
          initialized = true
        end
      end

      described_class.new(model: mock_model, hooks: [hook_provider])
      expect(initialized).to be true
    end

    it "registers tools from constructor" do
      tool = Strands.tool("test_tool", description: "A test", schema: {}) { "result" }
      agent = described_class.new(model: mock_model, tools: [tool])
      expect(agent.tool_registry.registered?("test_tool")).to be true
    end

    context "when model is not provided" do
      it "defaults to Strands::Models::Bedrock" do
        agent = nil
        expect { agent = described_class.new }.to output.to_stderr
        expect(agent.model).to be_a(Strands::Models::Bedrock)
      end

      it "uses the Bedrock provider's default model_id" do
        agent = nil
        expect { agent = described_class.new }.to output.to_stderr
        expect(agent.model.config[:model_id]).to eq(Strands::Models::Bedrock::DEFAULT_BEDROCK_MODEL_ID)
      end
    end
  end

  describe "#call" do
    it "returns a Result with the model response" do
      agent = described_class.new(model: mock_model)
      result = agent.call("Hello")
      expect(result).to be_a(Strands::Agent::Result)
      expect(result.stop_reason).to eq(:end_turn)
      expect(result.text).to eq("Test response")
    end

    it "adds user message to conversation history" do
      agent = described_class.new(model: mock_model)
      agent.call("Hello")
      expect(agent.messages.first[:role]).to eq(:user)
      expect(agent.messages.first[:content].first[:text]).to eq("Hello")
    end

    it "adds assistant message to conversation history" do
      agent = described_class.new(model: mock_model)
      agent.call("Hello")
      assistant_msgs = agent.messages.select { |m| m[:role] == :assistant }
      expect(assistant_msgs).not_to be_empty
    end

    it "fires BeforeInvocationEvent and AfterInvocationEvent" do
      events = []
      hook_provider = Object.new
      hook_provider.define_singleton_method(:register_hooks) do |registry|
        registry.add_callback(Strands::Hooks::BeforeInvocationEvent) { events << :before }
        registry.add_callback(Strands::Hooks::AfterInvocationEvent) { events << :after }
      end

      agent = described_class.new(model: mock_model, hooks: [hook_provider])
      agent.call("test")

      expect(events).to eq(%i[before after])
    end

    it "respects intervention that denies invocation" do
      deny_handler = Class.new(Strands::Interventions::Handler) do
        define_method(:name) { "denier" }
        define_method(:before_invocation) do |_event|
          Strands::Interventions::Deny.new(reason: "Not allowed")
        end
      end.new

      agent = described_class.new(model: mock_model, interventions: [deny_handler])
      result = agent.call("test")
      expect(result.text).to include("DENIED")
      expect(result.text).to include("Not allowed")
    end

    it "applies conversation manager before model call" do
      manager = Strands::Agent::SlidingWindowConversationManager.new(window_size: 4)
      agent = described_class.new(model: mock_model, conversation_manager: manager)

      # Call multiple times to build up history
      5.times { |i| agent.call("Message #{i}") }

      # Without manager, would be 10 messages. With window_size 4, stays bounded.
      # Window is applied before cycle, then cycle adds assistant msg.
      expect(agent.messages.length).to be < 10
    end
  end

  describe "#invoke" do
    it "is an alias for #call" do
      agent = described_class.new(model: mock_model)
      result = agent.invoke("Hello")
      expect(result.text).to eq("Test response")
    end
  end

  describe "#tool" do
    it "returns a ToolCaller proxy" do
      agent = described_class.new(model: mock_model)
      expect(agent.tool).to be_a(Strands::Agent::ToolCaller)
    end

    it "allows direct tool invocation" do
      tool = Strands.tool("reverse", description: "Reverses text", schema: {
                            properties: { text: { type: "string" } }, required: ["text"]
                          }) { |text:| text.reverse }

      agent = described_class.new(model: mock_model, tools: [tool])
      result = agent.tool.reverse(text: "hello")
      expect(result.status).to eq(:success)
      expect(result.content.first.text).to eq("olleh")
    end
  end
end
