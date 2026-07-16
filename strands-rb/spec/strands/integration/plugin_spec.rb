# frozen_string_literal: true

# Integration spec - Agent with plugins providing hooks and tools.

RSpec.describe "Strands Agent Plugin Integration" do
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

  describe "plugin with hooks and tools" do
    let(:metrics_plugin_class) do
      Class.new do
        include Strands::Plugins::Base

        plugin_name "metrics"

        attr_reader :events_log, :agent_ref

        define_method(:initialize) do
          @events_log = []
        end

        hook :track_model_call, event: Strands::Hooks::BeforeModelCallEvent
        define_method(:track_model_call) do |event|
          @events_log << { type: :model_call, agent: event.agent.name }
        end

        hook :track_tool_call, event: Strands::Hooks::BeforeToolCallEvent
        define_method(:track_tool_call) do |event|
          @events_log << { type: :tool_call, tool: event.tool_use.name }
        end

        plugin_tool :get_metrics, description: "Returns plugin metrics count", schema: {}
        define_method(:get_metrics) do |**_params|
          @events_log.length.to_s
        end

        define_method(:init_agent) do |agent|
          @agent_ref = agent
        end
      end
    end

    it "registers plugin tools with the agent" do
      plugin = metrics_plugin_class.new
      model = mock_model_class.new([text_response("OK")])
      agent = Strands::Agent::Agent.new(model: model, plugins: [plugin])

      expect(agent.tool_registry.registered?("get_metrics")).to be true
    end

    it "fires plugin hooks during agent execution" do
      plugin = metrics_plugin_class.new
      model = mock_model_class.new([text_response("Hello!")])
      agent = Strands::Agent::Agent.new(model: model, plugins: [plugin])

      agent.call("Hi")

      expect(plugin.events_log.length).to eq(1)
      expect(plugin.events_log[0][:type]).to eq(:model_call)
      expect(plugin.events_log[0][:agent]).to eq("Strands Agent")
    end

    it "fires tool hooks when model uses a tool" do
      plugin = metrics_plugin_class.new

      calculator = Strands.tool("calculator",
        description: "Math",
        schema: { properties: { expression: { type: "string" } }, required: ["expression"] }
      ) { |expression:| eval(expression).to_s }

      model = mock_model_class.new([
        tool_use_response("calculator", "t1", { expression: "1+1" }),
        text_response("2")
      ])

      agent = Strands::Agent::Agent.new(
        model: model,
        tools: [calculator],
        plugins: [plugin]
      )

      agent.call("What is 1+1?")

      model_calls = plugin.events_log.select { |e| e[:type] == :model_call }
      tool_calls = plugin.events_log.select { |e| e[:type] == :tool_call }

      expect(model_calls.length).to eq(2) # Before first and second model call
      expect(tool_calls.length).to eq(1)
      expect(tool_calls[0][:tool]).to eq("calculator")
    end

    it "receives agent reference via init_agent" do
      plugin = metrics_plugin_class.new
      model = mock_model_class.new([text_response("OK")])
      agent = Strands::Agent::Agent.new(model: model, plugins: [plugin])

      expect(plugin.agent_ref).to eq(agent)
    end

    it "plugin tool can be invoked by the model" do
      plugin = metrics_plugin_class.new

      model = mock_model_class.new([
        tool_use_response("get_metrics", "t1", {}),
        text_response("Metrics count: 1")
      ])

      agent = Strands::Agent::Agent.new(model: model, plugins: [plugin])
      result = agent.call("Show metrics")

      expect(result.stop_reason).to eq(:end_turn)
      expect(model.call_count).to eq(2)

      # Verify the tool executed and returned a result
      tool_result_msg = agent.messages.find { |m| (m[:content] || []).any? { |c| c[:tool_result] } }
      tr = tool_result_msg[:content][0][:tool_result]
      expect(tr.status).to eq(:success)
      # The metrics count should reflect the model calls before execution
      expect(tr.content.first.text).to be_a(String)
    end
  end

  describe "multiple plugins" do
    let(:audit_plugin_class) do
      Class.new do
        include Strands::Plugins::Base
        plugin_name "audit"

        attr_reader :messages_seen

        define_method(:initialize) { @messages_seen = [] }

        hook :on_message, event: Strands::Hooks::MessageAddedEvent
        define_method(:on_message) do |event|
          @messages_seen << event.message[:role]
        end
      end
    end

    let(:counter_plugin_class) do
      Class.new do
        include Strands::Plugins::Base
        plugin_name "counter"

        attr_reader :count

        define_method(:initialize) { @count = 0 }

        hook :on_model, event: Strands::Hooks::BeforeModelCallEvent
        define_method(:on_model) do |_event|
          @count += 1
        end

        plugin_tool :get_count, description: "Returns invocation count", schema: {}
        define_method(:get_count) do |**_params|
          @count.to_s
        end
      end
    end

    it "combines hooks and tools from multiple plugins" do
      audit = audit_plugin_class.new
      counter = counter_plugin_class.new

      model = mock_model_class.new([text_response("Done")])
      agent = Strands::Agent::Agent.new(
        model: model,
        plugins: [audit, counter]
      )

      expect(agent.tool_registry.registered?("get_count")).to be true

      agent.call("Hello")

      # Audit should have seen messages added
      expect(audit.messages_seen).to include(:user, :assistant)

      # Counter should have been incremented
      expect(counter.count).to eq(1)
    end
  end
end
