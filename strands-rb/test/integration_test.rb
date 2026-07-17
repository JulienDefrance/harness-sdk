# frozen_string_literal: true

# Integration test for the full Strands agent flow.
# Uses minitest (stdlib) since RSpec cannot be installed in this environment.
#
# Tests exercise: model streaming -> tool detection -> tool execution -> loop -> final response.

require "minitest/autorun"
require "json"

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "strands"

# ------------------------------------------------------------------
# Shared mock model that simulates streaming responses
# ------------------------------------------------------------------
class MockStreamingModel
  include Strands::Models::Base

  attr_reader :call_count, :received_messages

  def initialize(responses: [])
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

# Helper to build streaming events
module StreamHelper
  module_function

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
end

# ==================================================================
# Test: End-to-end agent flow with tool execution
# ==================================================================
class TestAgentEndToEnd < Minitest::Test
  def setup
    @calculator = Strands.tool("calculator",
      description: "Evaluates a math expression",
      schema: { properties: { expression: { type: "string" } }, required: ["expression"] }
    ) { |expression:| eval(expression).to_s }
  end

  def test_agent_with_tool_use_cycle
    model = MockStreamingModel.new(responses: [
      StreamHelper.tool_use_response("calculator", "tool_001", { expression: "2 + 2" }),
      StreamHelper.text_response("The answer is 4.")
    ])

    agent = Strands::Agent::Agent.new(
      model: model,
      tools: [@calculator],
      system_prompt: "You are a calculator assistant."
    )

    result = agent.call("What is 2 + 2?")

    assert_equal :end_turn, result.stop_reason
    assert_equal "The answer is 4.", result.text
    assert result.success?
    assert_equal 2, model.call_count

    # Verify conversation history
    assert_equal 4, agent.messages.length
    assert_equal :user, agent.messages[0][:role]
    assert_equal :assistant, agent.messages[1][:role]
    assert_equal :user, agent.messages[2][:role]       # tool result
    assert_equal :assistant, agent.messages[3][:role]  # final response

    # Verify tool result was appended correctly
    tool_result_content = agent.messages[2][:content]
    assert_equal 1, tool_result_content.length
    tool_result = tool_result_content[0][:tool_result]
    assert_equal "tool_001", tool_result.tool_use_id
    assert_equal :success, tool_result.status
    assert_equal "4", tool_result.content.first.text
  end

  def test_agent_simple_text_response
    model = MockStreamingModel.new(responses: [
      StreamHelper.text_response("Hello! How can I help you?")
    ])

    agent = Strands::Agent::Agent.new(model: model, system_prompt: "You are helpful.")
    result = agent.call("Hello")

    assert_equal :end_turn, result.stop_reason
    assert_equal "Hello! How can I help you?", result.text
    assert_equal 1, model.call_count
  end

  def test_agent_result_to_s
    model = MockStreamingModel.new(responses: [
      StreamHelper.text_response("Hello!")
    ])

    agent = Strands::Agent::Agent.new(model: model)
    result = agent.call("Hi")

    assert_equal "Hello!", result.to_s
  end
end

# ==================================================================
# Test: Agent defaults to Bedrock when no model is given
# ==================================================================
class TestAgentDefaultModel < Minitest::Test
  def test_agent_defaults_to_bedrock_when_model_omitted
    agent = capture_io_ignoring_warnings { Strands::Agent::Agent.new }

    assert_kind_of Strands::Models::Bedrock, agent.model
  end

  def test_agent_uses_bedrock_default_model_id
    agent = capture_io_ignoring_warnings { Strands::Agent::Agent.new }

    assert_equal Strands::Models::Bedrock::DEFAULT_BEDROCK_MODEL_ID, agent.model.config[:model_id]
  end

  def test_agent_respects_explicit_model_over_default
    model = MockStreamingModel.new(responses: [StreamHelper.text_response("hi")])
    agent = Strands::Agent::Agent.new(model: model)

    assert_same model, agent.model
  end

  def test_bedrock_warns_when_model_id_omitted
    _out, err = capture_io { Strands::Models::Bedrock.new }

    assert_match(/using default modelId/, err)
  end

  def test_bedrock_does_not_warn_when_model_id_given
    _out, err = capture_io { Strands::Models::Bedrock.new(model_id: "anthropic.claude-3-5-sonnet-20241022-v2:0") }

    assert_empty err
  end

  private

  # Swallows the "using default modelId" warning emitted on $stderr so it
  # doesn't clutter test output, while still returning the block's result.
  def capture_io_ignoring_warnings
    result = nil
    capture_io { result = yield }
    result
  end
end

# ==================================================================
# Test: Multiple tools with sequential calls
# ==================================================================
class TestMultiToolAgent < Minitest::Test
  def setup
    @calculator = Strands.tool("calculator",
      description: "Evaluates math",
      schema: { properties: { expression: { type: "string" } }, required: ["expression"] }
    ) { |expression:| eval(expression).to_s }

    @reverse = Strands.tool("reverse",
      description: "Reverses a string",
      schema: { properties: { text: { type: "string" } }, required: ["text"] }
    ) { |text:| text.reverse }
  end

  def test_sequential_tool_calls
    model = MockStreamingModel.new(responses: [
      StreamHelper.tool_use_response("calculator", "tool_001", { expression: "3 * 7" }),
      StreamHelper.tool_use_response("reverse", "tool_002", { text: "hello" }),
      StreamHelper.text_response("Done! 3*7=21 and reversed hello is olleh.")
    ])

    agent = Strands::Agent::Agent.new(
      model: model,
      tools: [@calculator, @reverse],
      system_prompt: "Use tools to help."
    )

    result = agent.call("Calculate 3*7 and reverse 'hello'")

    assert_equal :end_turn, result.stop_reason
    assert result.text.include?("Done!")
    assert_equal 3, model.call_count

    # Verify both tools were executed
    tool_results = agent.messages.select { |m| (m[:content] || []).any? { |c| c[:tool_result] } }
    assert_equal 2, tool_results.length

    # First tool result: calculator
    first_result = tool_results[0][:content][0][:tool_result]
    assert_equal "tool_001", first_result.tool_use_id
    assert_equal "21", first_result.content.first.text

    # Second tool result: reverse
    second_result = tool_results[1][:content][0][:tool_result]
    assert_equal "tool_002", second_result.tool_use_id
    assert_equal "olleh", second_result.content.first.text
  end

  def test_tool_not_found_returns_error
    model = MockStreamingModel.new(responses: [
      StreamHelper.tool_use_response("nonexistent_tool", "tool_001", {}),
      StreamHelper.text_response("Sorry, could not find that tool.")
    ])

    agent = Strands::Agent::Agent.new(
      model: model,
      tools: [@calculator]
    )

    result = agent.call("Use a tool")

    assert_equal :end_turn, result.stop_reason
    # Tool result should have error status
    tool_result_msg = agent.messages.find { |m| (m[:content] || []).any? { |c| c[:tool_result] } }
    tr = tool_result_msg[:content][0][:tool_result]
    assert_equal :error, tr.status
    assert tr.content.first.text.include?("not found")
  end
end

# ==================================================================
# Test: Intervention handler that denies a tool call
# ==================================================================
class DenyCalculatorHandler < Strands::Interventions::Handler
  def name
    "deny_calculator"
  end

  def before_tool_call(event)
    if event.tool_use.name == "calculator"
      Strands::Interventions::Deny.new(reason: "Calculator is disabled for safety")
    else
      Strands::Interventions::Proceed.new
    end
  end
end

class TestInterventionAgent < Minitest::Test
  def setup
    @calculator = Strands.tool("calculator",
      description: "Evaluates math",
      schema: { properties: { expression: { type: "string" } }, required: ["expression"] }
    ) { |expression:| eval(expression).to_s }

    @reverse = Strands.tool("reverse",
      description: "Reverses a string",
      schema: { properties: { text: { type: "string" } }, required: ["text"] }
    ) { |text:| text.reverse }
  end

  def test_intervention_denies_tool_call
    model = MockStreamingModel.new(responses: [
      StreamHelper.tool_use_response("calculator", "tool_001", { expression: "2 + 2" }),
      StreamHelper.text_response("I cannot use the calculator.")
    ])

    handler = DenyCalculatorHandler.new
    agent = Strands::Agent::Agent.new(
      model: model,
      tools: [@calculator],
      interventions: [handler]
    )

    result = agent.call("What is 2+2?")

    assert_equal :end_turn, result.stop_reason
    assert_equal "I cannot use the calculator.", result.text

    # Verify tool result has error status due to denial
    tool_result_msg = agent.messages.find { |m| (m[:content] || []).any? { |c| c[:tool_result] } }
    assert tool_result_msg, "Expected a tool_result message"
    tr = tool_result_msg[:content][0][:tool_result]
    assert_equal :error, tr.status
    assert tr.content.first.text.include?("DENIED")
    assert tr.content.first.text.include?("Calculator is disabled for safety")
  end

  def test_intervention_allows_non_target_tools
    model = MockStreamingModel.new(responses: [
      StreamHelper.tool_use_response("reverse", "tool_002", { text: "world" }),
      StreamHelper.text_response("Reversed: dlrow")
    ])

    handler = DenyCalculatorHandler.new
    agent = Strands::Agent::Agent.new(
      model: model,
      tools: [@calculator, @reverse],
      interventions: [handler]
    )

    result = agent.call("Reverse 'world'")

    assert_equal :end_turn, result.stop_reason
    # The reverse tool should have worked normally
    tool_result_msg = agent.messages.find { |m| (m[:content] || []).any? { |c| c[:tool_result] } }
    tr = tool_result_msg[:content][0][:tool_result]
    assert_equal :success, tr.status
    assert_equal "dlrow", tr.content.first.text
  end
end

# ==================================================================
# Test: Plugin that provides both hooks and tools
# ==================================================================
class AuditPlugin
  include Strands::Plugins::Base

  plugin_name "audit"

  attr_reader :model_call_log, :agent_ref

  def initialize
    @model_call_log = []
  end

  hook :on_before_model, event: Strands::Hooks::BeforeModelCallEvent
  def on_before_model(event)
    @model_call_log << { time: Time.now, agent_name: event.agent.name }
  end

  plugin_tool :audit_count, description: "Returns number of model calls", schema: {}
  def audit_count(**_params)
    @model_call_log.length.to_s
  end

  def init_agent(agent)
    @agent_ref = agent
  end
end

class TestPluginAgent < Minitest::Test
  def test_plugin_provides_hooks_and_tools
    plugin = AuditPlugin.new

    model = MockStreamingModel.new(responses: [
      StreamHelper.text_response("Hello!")
    ])

    agent = Strands::Agent::Agent.new(
      model: model,
      plugins: [plugin]
    )

    # Plugin tool should be registered
    assert agent.tool_registry.registered?("audit_count")

    # Invoke agent
    result = agent.call("Hi")
    assert_equal "Hello!", result.text

    # Plugin hook should have been triggered
    assert_equal 1, plugin.model_call_log.length
    assert_equal "Strands Agent", plugin.model_call_log[0][:agent_name]

    # Plugin should have received agent reference
    assert_equal agent, plugin.agent_ref
  end

  def test_plugin_tool_execution_via_model
    plugin = AuditPlugin.new

    model = MockStreamingModel.new(responses: [
      StreamHelper.tool_use_response("audit_count", "tool_001", {}),
      StreamHelper.text_response("There have been 1 model calls.")
    ])

    agent = Strands::Agent::Agent.new(
      model: model,
      plugins: [plugin]
    )

    result = agent.call("How many model calls?")

    assert_equal :end_turn, result.stop_reason
    assert_equal 2, model.call_count

    # Plugin hook should have fired for both model calls
    assert_equal 2, plugin.model_call_log.length
  end
end

# ==================================================================
# Test: Callback handler receives streaming events
# ==================================================================
class TestCallbackHandler < Minitest::Test
  def test_callback_handler_receives_text_events
    received_chunks = []
    handler = ->(data: nil, complete: false, **_kwargs) {
      received_chunks << { data: data, complete: complete }
    }

    model = MockStreamingModel.new(responses: [
      StreamHelper.text_response("Hello World!")
    ])

    agent = Strands::Agent::Agent.new(
      model: model,
      callback_handler: handler
    )

    agent.call("Hi")

    # Should have received text chunk and completion signal
    text_events = received_chunks.select { |c| c[:data] && !c[:data].empty? }
    assert text_events.length >= 1
    assert_equal "Hello World!", text_events.map { |e| e[:data] }.join

    complete_events = received_chunks.select { |c| c[:complete] }
    assert complete_events.length >= 1
  end
end

# ==================================================================
# Test: Max turns limit
# ==================================================================
class TestMaxTurns < Minitest::Test
  def test_agent_stops_at_max_turns
    # Model always requests tool use, creating an infinite loop
    infinite_tool_response = StreamHelper.tool_use_response("echo", "tool_inf", { text: "loop" })

    model = MockStreamingModel.new(responses: [infinite_tool_response])

    echo = Strands.tool("echo",
      description: "Echoes text",
      schema: { properties: { text: { type: "string" } }, required: ["text"] }
    ) { |text:| text }

    agent = Strands::Agent::Agent.new(
      model: model,
      tools: [echo],
      max_turns: 3
    )

    result = agent.call("Loop forever")

    assert_equal :limit_turns, result.stop_reason
    assert_equal 3, model.call_count
  end
end

# ==================================================================
# Test: Module loading verification
# ==================================================================
class TestModuleLoading < Minitest::Test
  def test_all_modules_load_without_errors
    # Force load all top-level autoloaded modules
    assert Strands::Types
    assert Strands::Models
    assert Strands::Tools
    assert Strands::EventLoop
    assert Strands::Hooks
    assert Strands::Interventions
    assert Strands::Plugins
    assert Strands::Handlers
    assert Strands::Memory
    assert Strands::Storage
    assert Strands::Session
    assert Strands::Telemetry
    assert Strands::Agent
  end

  def test_key_classes_are_accessible
    assert Strands::Agent::Agent
    assert Strands::Agent::Result
    assert Strands::Agent::ConversationManager
    assert Strands::Agent::NullConversationManager
    assert Strands::Agent::SlidingWindowConversationManager
    assert Strands::Models::Base
    assert Strands::Tools::Definition
    assert Strands::Tools::DSL
    assert Strands::Tools::Registry
    assert Strands::Tools::Executor
    assert Strands::Tools::ToolContext
    assert Strands::Tools::MCPClient
    assert Strands::Tools::ToolProvider
    assert Strands::EventLoop::Cycle
    assert Strands::EventLoop::RetryStrategy
    assert Strands::Hooks::Registry
    assert Strands::Hooks::BeforeModelCallEvent
    assert Strands::Hooks::AfterModelCallEvent
    assert Strands::Hooks::BeforeToolCallEvent
    assert Strands::Hooks::AfterToolCallEvent
    assert Strands::Hooks::BeforeInvocationEvent
    assert Strands::Hooks::AfterInvocationEvent
    assert Strands::Hooks::MessageAddedEvent
    assert Strands::Hooks::AgentInitializedEvent
    assert Strands::Interventions::Handler
    assert Strands::Interventions::Proceed
    assert Strands::Interventions::Deny
    assert Strands::Interventions::Guide
    assert Strands::Interventions::Transform
    assert Strands::Interventions::Registry
    assert Strands::Plugins::Base
    assert Strands::Plugins::Discovery
    assert Strands::Handlers::CallbackHandler
    assert Strands::Handlers::Null
    assert Strands::Handlers::Printing
    assert Strands::Memory::Store
    assert Strands::Memory::MemoryEntry
    assert Strands::Memory::InMemoryStore
    assert Strands::Memory::Manager
    assert Strands::Storage::Base
    assert Strands::Storage::InMemory
    assert Strands::Storage::LocalFile
    assert Strands::Session::Manager
    assert Strands::Session::FileManager
    assert Strands::Telemetry::Metrics
    assert Strands::Telemetry::Tracer
    assert Strands::Types::Streaming::StreamEvent
    assert Strands::Types::Tools::ToolUse
    assert Strands::Types::Tools::ToolResult
    assert Strands::Types::Tools::ToolSpec
    assert Strands::Types::Tools::ToolResultContent
    assert Strands::Types::Exceptions
  end

  def test_strands_tool_dsl_creates_definition
    tool = Strands.tool("test_tool",
      description: "A test tool",
      schema: { properties: { input: { type: "string" } }, required: ["input"] }
    ) { |input:| "got: #{input}" }

    assert_instance_of Strands::Tools::Definition, tool
    assert_equal "test_tool", tool.name
    assert_equal "A test tool", tool.description
  end
end
