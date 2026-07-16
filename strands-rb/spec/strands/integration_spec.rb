# frozen_string_literal: true

# Integration spec - End-to-end agent flow with mock model and tools.
#
# Tests the full cycle: model streaming -> tool detection -> tool execution
# -> loop back to model -> final text response -> AgentResult.

RSpec.describe "Strands Agent Integration" do
  # Helper to build a text-only streaming response
  def text_response(text, stop_reason: :end_turn)
    proc do |_messages, _tools, &block|
      block.call(Strands::Types::Streaming::StreamEvent.new(
        message_start: Strands::Types::Streaming::MessageStartEvent.new(role: :assistant)
      ))
      block.call(Strands::Types::Streaming::StreamEvent.new(
        content_block_delta: Strands::Types::Streaming::ContentBlockDeltaEvent.new(
          content_block_index: 0,
          delta: Strands::Types::Streaming::ContentBlockDelta.new(text: text)
        )
      ))
      block.call(Strands::Types::Streaming::StreamEvent.new(
        content_block_stop: Strands::Types::Streaming::ContentBlockStopEvent.new(content_block_index: 0)
      ))
      block.call(Strands::Types::Streaming::StreamEvent.new(
        message_stop: Strands::Types::Streaming::MessageStopEvent.new(stop_reason: stop_reason)
      ))
    end
  end

  # Helper to build a tool-use streaming response
  def tool_use_response(tool_name, tool_use_id, input_hash)
    proc do |_messages, _tools, &block|
      block.call(Strands::Types::Streaming::StreamEvent.new(
        message_start: Strands::Types::Streaming::MessageStartEvent.new(role: :assistant)
      ))
      block.call(Strands::Types::Streaming::StreamEvent.new(
        content_block_start: Strands::Types::Streaming::ContentBlockStartEvent.new(
          content_block_index: 0,
          start: Strands::Types::Streaming::ContentBlockStart.new(
            tool_use: Strands::Types::Streaming::ContentBlockStartToolUse.new(
              name: tool_name,
              tool_use_id: tool_use_id
            )
          )
        )
      ))
      block.call(Strands::Types::Streaming::StreamEvent.new(
        content_block_delta: Strands::Types::Streaming::ContentBlockDeltaEvent.new(
          content_block_index: 0,
          delta: Strands::Types::Streaming::ContentBlockDelta.new(
            tool_use: Strands::Types::Streaming::ContentBlockDeltaToolUse.new(
              input: JSON.generate(input_hash)
            )
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
  end

  # Mock model that takes a list of response procs
  let(:mock_model_class) do
    Class.new do
      include Strands::Models::Base

      attr_reader :call_count, :received_messages

      def initialize(responses)
        @responses = responses
        @call_count = 0
        @received_messages = []
        @config = {}
      end

      def stream(messages, system_prompt: nil, tools: nil, tool_choice: nil, **kwargs)
        @call_count += 1
        @received_messages << messages.dup
        response = @responses[@call_count - 1] || @responses.last
        response.call(messages, tools) { |event| yield event }
      end

      def update_config(**opts)
        @config.merge!(opts)
      end

      def get_config
        @config.dup
      end
    end
  end

  let(:calculator) do
    Strands.tool("calculator",
      description: "Evaluates math expressions",
      schema: { properties: { expression: { type: "string" } }, required: ["expression"] }
    ) { |expression:| eval(expression).to_s }
  end

  describe "simple text response" do
    it "returns an AgentResult with the model text" do
      model = mock_model_class.new([text_response("Hello! I am an AI.")])
      agent = Strands::Agent::Agent.new(model: model, system_prompt: "You are helpful.")

      result = agent.call("Hello")

      expect(result).to be_a(Strands::Agent::Result)
      expect(result.stop_reason).to eq(:end_turn)
      expect(result.text).to eq("Hello! I am an AI.")
      expect(result.success?).to be true
      expect(model.call_count).to eq(1)
    end
  end

  describe "tool use cycle" do
    it "executes a tool and returns the final response" do
      model = mock_model_class.new([
        tool_use_response("calculator", "tool_001", { expression: "6 * 7" }),
        text_response("The result of 6 * 7 is 42.")
      ])

      agent = Strands::Agent::Agent.new(
        model: model,
        tools: [calculator],
        system_prompt: "You are a math assistant."
      )

      result = agent.call("What is 6 times 7?")

      expect(result.stop_reason).to eq(:end_turn)
      expect(result.text).to eq("The result of 6 * 7 is 42.")
      expect(model.call_count).to eq(2)
    end

    it "appends tool results to conversation history" do
      model = mock_model_class.new([
        tool_use_response("calculator", "tool_001", { expression: "10 + 5" }),
        text_response("15")
      ])

      agent = Strands::Agent::Agent.new(model: model, tools: [calculator])
      agent.call("Add 10 and 5")

      # Messages: user, assistant (tool_use), user (tool_result), assistant (final)
      expect(agent.messages.length).to eq(4)
      expect(agent.messages[0][:role]).to eq(:user)
      expect(agent.messages[1][:role]).to eq(:assistant)
      expect(agent.messages[2][:role]).to eq(:user)
      expect(agent.messages[3][:role]).to eq(:assistant)

      # Verify tool result
      tool_result = agent.messages[2][:content][0][:tool_result]
      expect(tool_result.tool_use_id).to eq("tool_001")
      expect(tool_result.status).to eq(:success)
      expect(tool_result.content.first.text).to eq("15")
    end
  end

  describe "callback handler" do
    it "receives streaming text events" do
      chunks = []
      handler = ->(data: nil, complete: false, **_kw) {
        chunks << { data: data, complete: complete }
      }

      model = mock_model_class.new([text_response("Streaming works!")])
      agent = Strands::Agent::Agent.new(model: model, callback_handler: handler)
      agent.call("Test streaming")

      text_chunks = chunks.select { |c| c[:data] && !c[:data].empty? }
      expect(text_chunks.map { |c| c[:data] }.join).to eq("Streaming works!")
      expect(chunks.any? { |c| c[:complete] }).to be true
    end
  end

  describe "max turns limit" do
    it "stops after max_turns iterations" do
      # Model always requests tool use, creating an infinite loop
      always_tool = tool_use_response("calculator", "tool_loop", { expression: "1" })
      model = mock_model_class.new([always_tool])

      agent = Strands::Agent::Agent.new(
        model: model,
        tools: [calculator],
        max_turns: 3
      )

      result = agent.call("Loop")

      expect(result.stop_reason).to eq(:limit_turns)
      expect(model.call_count).to eq(3)
    end
  end

  describe "hooks lifecycle" do
    it "fires BeforeInvocation and AfterInvocation events" do
      events_fired = []

      hook_provider = Object.new
      def hook_provider.register_hooks(registry)
        registry.add_callback(Strands::Hooks::BeforeInvocationEvent) do |event|
          event.agent.instance_variable_get(:@_test_events) << :before_invocation
        end
        registry.add_callback(Strands::Hooks::AfterInvocationEvent) do |event|
          event.agent.instance_variable_get(:@_test_events) << :after_invocation
        end
      end

      model = mock_model_class.new([text_response("Hi")])
      agent = Strands::Agent::Agent.new(model: model, hooks: [hook_provider])
      agent.instance_variable_set(:@_test_events, events_fired)

      agent.call("Hello")

      expect(events_fired).to eq([:before_invocation, :after_invocation])
    end
  end
end
