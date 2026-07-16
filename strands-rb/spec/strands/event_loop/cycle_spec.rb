# frozen_string_literal: true

require "spec_helper"

RSpec.describe Strands::EventLoop::Cycle do
  # Mock model that streams responses
  let(:mock_model) do
    model = Object.new
    model.define_singleton_method(:stream) do |messages, system_prompt: nil, tools: nil, tool_choice: nil, **kwargs, &block|
      # Default: return simple text response
      block.call(Strands::Types::Streaming::StreamEvent.new(
                   message_start: Strands::Types::Streaming::MessageStartEvent.new(role: :assistant)
                 ))
      block.call(Strands::Types::Streaming::StreamEvent.new(
                   content_block_delta: Strands::Types::Streaming::ContentBlockDeltaEvent.new(
                     content_block_index: 0,
                     delta: Strands::Types::Streaming::ContentBlockDelta.new(text: "Hello!")
                   )
                 ))
      block.call(Strands::Types::Streaming::StreamEvent.new(
                   content_block_stop: Strands::Types::Streaming::ContentBlockStopEvent.new(content_block_index: 0)
                 ))
      block.call(Strands::Types::Streaming::StreamEvent.new(
                   message_stop: Strands::Types::Streaming::MessageStopEvent.new(stop_reason: :end_turn)
                 ))
    end
    model
  end

  let(:tool_registry) { Strands::Tools::Registry.new }
  let(:hook_registry) { Strands::Hooks::Registry.new }
  let(:messages) { [{ role: :user, content: [{ text: "Hi" }] }] }

  let(:agent) do
    agent = Object.new
    model_ref = mock_model
    registry_ref = tool_registry
    hooks_ref = hook_registry
    msgs_ref = messages
    agent.define_singleton_method(:model) { model_ref }
    agent.define_singleton_method(:tool_registry) { registry_ref }
    agent.define_singleton_method(:hook_registry) { hooks_ref }
    agent.define_singleton_method(:messages) { msgs_ref }
    agent.define_singleton_method(:messages=) { |v| }
    agent.define_singleton_method(:system_prompt) { "You are helpful" }
    agent.define_singleton_method(:callback_handler) { nil }
    agent
  end

  describe "#run" do
    it "processes a simple text response and returns end_turn" do
      cycle = described_class.new(agent: agent)
      result = cycle.run(invocation_state: {})

      expect(result[:stop_reason]).to eq(:end_turn)
      expect(result[:message][:role]).to eq(:assistant)
      expect(result[:message][:content].first[:text]).to eq("Hello!")
    end

    it "appends assistant message to agent messages" do
      cycle = described_class.new(agent: agent)
      cycle.run(invocation_state: {})

      # Messages should have been appended (user + assistant)
      expect(messages.length).to be >= 2
    end

    it "stops at max_turns when tool loops are infinite" do
      # Model that always returns tool_use
      call_count = 0
      infinite_model = Object.new
      infinite_model.define_singleton_method(:stream) do |messages, system_prompt: nil, tools: nil, tool_choice: nil, **kwargs, &block|
        call_count += 1
        block.call(Strands::Types::Streaming::StreamEvent.new(
                     message_start: Strands::Types::Streaming::MessageStartEvent.new(role: :assistant)
                   ))
        block.call(Strands::Types::Streaming::StreamEvent.new(
                     content_block_start: Strands::Types::Streaming::ContentBlockStartEvent.new(
                       content_block_index: 0,
                       start: Strands::Types::Streaming::ContentBlockStart.new(
                         tool_use: Strands::Types::Streaming::ContentBlockStartToolUse.new(
                           name: "test_tool",
                           tool_use_id: "id_#{call_count}"
                         )
                       )
                     )
                   ))
        block.call(Strands::Types::Streaming::StreamEvent.new(
                     content_block_delta: Strands::Types::Streaming::ContentBlockDeltaEvent.new(
                       content_block_index: 0,
                       delta: Strands::Types::Streaming::ContentBlockDelta.new(
                         tool_use: Strands::Types::Streaming::ContentBlockDeltaToolUse.new(input: '{}')
                       )
                     )
                   ))
        block.call(Strands::Types::Streaming::StreamEvent.new(
                     content_block_stop: Strands::Types::Streaming::ContentBlockStopEvent.new(content_block_index: 0)
                   ))
        block.call(Strands::Types::Streaming::StreamEvent.new(
                     message_stop: Strands::Types::Streaming::MessageStopEvent.new(stop_reason: :tool_use)
                   ))
      end

      # Register a tool so execution succeeds
      tool_def = Strands::Tools::Definition.new(
        name: "test_tool",
        description: "A test tool",
        input_schema: {},
        callable: ->(_input, **_kwargs) { "done" }
      )
      tool_registry.register(tool_def)

      infinite_agent = Object.new
      msgs = [{ role: :user, content: [{ text: "loop" }] }]
      infinite_agent.define_singleton_method(:model) { infinite_model }
      infinite_agent.define_singleton_method(:tool_registry) { tool_registry }
      infinite_agent.define_singleton_method(:hook_registry) { hook_registry }
      infinite_agent.define_singleton_method(:messages) { msgs }
      infinite_agent.define_singleton_method(:messages=) { |v| }
      infinite_agent.define_singleton_method(:system_prompt) { nil }
      infinite_agent.define_singleton_method(:callback_handler) { nil }

      cycle = described_class.new(agent: infinite_agent, max_turns: 3)
      result = cycle.run(invocation_state: {})

      expect(result[:stop_reason]).to eq(:limit_turns)
    end

    it "fires hook events at lifecycle points" do
      events_fired = []

      hook_registry.add_callback(Strands::Hooks::BeforeModelCallEvent) do |event|
        events_fired << :before_model
      end
      hook_registry.add_callback(Strands::Hooks::AfterModelCallEvent) do |event|
        events_fired << :after_model
      end
      hook_registry.add_callback(Strands::Hooks::MessageAddedEvent) do |event|
        events_fired << :message_added
      end

      cycle = described_class.new(agent: agent)
      cycle.run(invocation_state: {})

      expect(events_fired).to include(:before_model)
      expect(events_fired).to include(:after_model)
      expect(events_fired).to include(:message_added)
    end

    it "respects intervention Deny on model call" do
      hook_registry.add_callback(Strands::Hooks::BeforeModelCallEvent) do |event|
        event.cancel = "Denied by test"
      end

      cycle = described_class.new(agent: agent)
      result = cycle.run(invocation_state: {})

      expect(result[:stop_reason]).to eq(:end_turn)
      expect(result[:message][:content].first[:text]).to eq("Denied by test")
    end
  end
end
