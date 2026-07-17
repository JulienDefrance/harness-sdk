# frozen_string_literal: true

# Integration spec - Agent with multiple tools and sequential tool calls.

RSpec.describe "Strands Agent Multi-Tool Integration" do
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

  let(:mock_model_class) do
    Class.new do
      include Strands::Models::Base

      attr_reader :call_count

      def initialize(responses)
        @responses = responses
        @call_count = 0
        @config = {}
      end

      def stream(messages, system_prompt: nil, tools: nil, tool_choice: nil, **kwargs)
        @call_count += 1
        response = @responses[@call_count - 1] || @responses.last
        response.call(messages, tools) { |event| yield event }
      end

      def update_config(**opts); @config.merge!(opts); end
      def get_config; @config.dup; end
    end
  end

  let(:calculator) do
    Strands.tool("calculator",
      description: "Evaluates math expressions",
      schema: { properties: { expression: { type: "string" } }, required: ["expression"] }
    ) { |expression:| eval(expression).to_s }
  end

  let(:reverse) do
    Strands.tool("reverse",
      description: "Reverses a string",
      schema: { properties: { text: { type: "string" } }, required: ["text"] }
    ) { |text:| text.reverse }
  end

  let(:upcase) do
    Strands.tool("upcase",
      description: "Uppercases a string",
      schema: { properties: { text: { type: "string" } }, required: ["text"] }
    ) { |text:| text.upcase }
  end

  describe "sequential tool calls across turns" do
    it "executes multiple tools in sequence across model turns" do
      model = mock_model_class.new([
        tool_use_response("calculator", "t1", { expression: "100 / 4" }),
        tool_use_response("reverse", "t2", { text: "strands" }),
        tool_use_response("upcase", "t3", { text: "hello" }),
        text_response("Results: 25, sdnarts, HELLO")
      ])

      agent = Strands::Agent::Agent.new(
        model: model,
        tools: [calculator, reverse, upcase]
      )

      result = agent.call("Compute, reverse, and upcase")

      expect(result.stop_reason).to eq(:end_turn)
      expect(result.text).to include("Results")
      expect(model.call_count).to eq(4)

      # Verify each tool produced the correct result
      tool_results = agent.messages.select { |m| (m[:content] || []).any? { |c| c[:tool_result] } }
      expect(tool_results.length).to eq(3)

      results_text = tool_results.map { |m| m[:content][0][:tool_result].content.first.text }
      expect(results_text).to eq(["25", "sdnarts", "HELLO"])
    end
  end

  describe "tool registry contains all tools" do
    it "registers multiple tools and they are all available" do
      model = mock_model_class.new([text_response("OK")])
      agent = Strands::Agent::Agent.new(
        model: model,
        tools: [calculator, reverse, upcase]
      )

      expect(agent.tool_registry.size).to eq(3)
      expect(agent.tool_registry.registered?("calculator")).to be true
      expect(agent.tool_registry.registered?("reverse")).to be true
      expect(agent.tool_registry.registered?("upcase")).to be true
    end
  end

  describe "tool that returns a hash" do
    it "serializes hash results as JSON content" do
      lookup = Strands.tool("lookup",
        description: "Looks up data",
        schema: { properties: { key: { type: "string" } }, required: ["key"] }
      ) { |key:| { found: true, value: "data_for_#{key}" } }

      model = mock_model_class.new([
        tool_use_response("lookup", "t1", { key: "test" }),
        text_response("Found the data.")
      ])

      agent = Strands::Agent::Agent.new(model: model, tools: [lookup])
      agent.call("Look up test")

      tool_result_msg = agent.messages.find { |m| (m[:content] || []).any? { |c| c[:tool_result] } }
      tr = tool_result_msg[:content][0][:tool_result]
      expect(tr.status).to eq(:success)
      expect(tr.content.first.json).to eq({ found: true, value: "data_for_test" })
    end
  end

  describe "tool that raises an error" do
    it "returns error status without crashing the agent" do
      failing_tool = Strands.tool("fail",
        description: "Always fails",
        schema: {}
      ) { raise "Something went wrong!" }

      model = mock_model_class.new([
        tool_use_response("fail", "t1", {}),
        text_response("The tool encountered an error.")
      ])

      agent = Strands::Agent::Agent.new(model: model, tools: [failing_tool])
      result = agent.call("Run the failing tool")

      expect(result.stop_reason).to eq(:end_turn)
      expect(result.text).to eq("The tool encountered an error.")

      tool_result_msg = agent.messages.find { |m| (m[:content] || []).any? { |c| c[:tool_result] } }
      tr = tool_result_msg[:content][0][:tool_result]
      expect(tr.status).to eq(:error)
      expect(tr.content.first.text).to include("RuntimeError")
      expect(tr.content.first.text).to include("Something went wrong!")
    end
  end
end
