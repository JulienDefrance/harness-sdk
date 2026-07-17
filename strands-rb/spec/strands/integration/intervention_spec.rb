# frozen_string_literal: true

# Integration spec - Agent with intervention handlers that deny or guide tool calls.

RSpec.describe "Strands Agent Intervention Integration" do
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
      description: "Evaluates math",
      schema: { properties: { expression: { type: "string" } }, required: ["expression"] }
    ) { |expression:| eval(expression).to_s }
  end

  let(:reverse) do
    Strands.tool("reverse",
      description: "Reverses text",
      schema: { properties: { text: { type: "string" } }, required: ["text"] }
    ) { |text:| text.reverse }
  end

  describe "Deny intervention on tool call" do
    let(:deny_handler_class) do
      Class.new(Strands::Interventions::Handler) do
        define_method(:name) { "deny_calculator" }

        define_method(:before_tool_call) do |event|
          if event.tool_use.name == "calculator"
            Strands::Interventions::Deny.new(reason: "Calculator not allowed")
          else
            Strands::Interventions::Proceed.new
          end
        end
      end
    end

    it "prevents the tool from executing and returns denial message" do
      model = mock_model_class.new([
        tool_use_response("calculator", "tool_001", { expression: "5 * 5" }),
        text_response("I could not use the calculator.")
      ])

      handler = deny_handler_class.new
      agent = Strands::Agent::Agent.new(
        model: model,
        tools: [calculator],
        interventions: [handler]
      )

      result = agent.call("What is 5 * 5?")

      expect(result.stop_reason).to eq(:end_turn)
      expect(result.text).to eq("I could not use the calculator.")

      # Tool result should contain denial message
      tool_result_msg = agent.messages.find { |m| (m[:content] || []).any? { |c| c[:tool_result] } }
      tr = tool_result_msg[:content][0][:tool_result]
      expect(tr.status).to eq(:error)
      expect(tr.content.first.text).to include("DENIED")
      expect(tr.content.first.text).to include("Calculator not allowed")
    end

    it "allows non-targeted tools to proceed" do
      model = mock_model_class.new([
        tool_use_response("reverse", "tool_001", { text: "hello" }),
        text_response("Reversed: olleh")
      ])

      handler = deny_handler_class.new
      agent = Strands::Agent::Agent.new(
        model: model,
        tools: [calculator, reverse],
        interventions: [handler]
      )

      result = agent.call("Reverse hello")

      tool_result_msg = agent.messages.find { |m| (m[:content] || []).any? { |c| c[:tool_result] } }
      tr = tool_result_msg[:content][0][:tool_result]
      expect(tr.status).to eq(:success)
      expect(tr.content.first.text).to eq("olleh")
    end
  end

  describe "Deny intervention on invocation" do
    let(:deny_all_handler_class) do
      Class.new(Strands::Interventions::Handler) do
        define_method(:name) { "deny_all" }

        define_method(:before_invocation) do |_event|
          Strands::Interventions::Deny.new(reason: "All invocations are blocked")
        end
      end
    end

    it "cancels the invocation before the model is called" do
      model = mock_model_class.new([text_response("Should not reach here")])

      handler = deny_all_handler_class.new
      agent = Strands::Agent::Agent.new(
        model: model,
        tools: [calculator],
        interventions: [handler]
      )

      result = agent.call("Hello")

      expect(result.stop_reason).to eq(:end_turn)
      expect(result.text).to include("DENIED")
      expect(result.text).to include("All invocations are blocked")
      expect(model.call_count).to eq(0) # Model was never called
    end
  end

  describe "multiple intervention handlers" do
    let(:logging_handler_class) do
      Class.new(Strands::Interventions::Handler) do
        attr_reader :logged_tools

        define_method(:initialize) do
          @logged_tools = []
        end

        define_method(:name) { "logger" }

        define_method(:before_tool_call) do |event|
          @logged_tools << event.tool_use.name
          Strands::Interventions::Proceed.new
        end
      end
    end

    let(:deny_handler_class) do
      Class.new(Strands::Interventions::Handler) do
        define_method(:name) { "deny_calc" }

        define_method(:before_tool_call) do |event|
          if event.tool_use.name == "calculator"
            Strands::Interventions::Deny.new(reason: "blocked")
          else
            Strands::Interventions::Proceed.new
          end
        end
      end
    end

    it "processes handlers in order and short-circuits on Deny" do
      model = mock_model_class.new([
        tool_use_response("calculator", "t1", { expression: "1+1" }),
        text_response("Blocked")
      ])

      logger = logging_handler_class.new
      denier = deny_handler_class.new
      agent = Strands::Agent::Agent.new(
        model: model,
        tools: [calculator],
        interventions: [logger, denier]
      )

      agent.call("Calc")

      # Logger should have seen the tool call before denier blocked it
      expect(logger.logged_tools).to eq(["calculator"])
    end
  end
end
