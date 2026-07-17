# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "strands"
require "minitest/autorun"

# ============================================================
# Hooks Events Tests
# ============================================================
class TestHooksEvents < Minitest::Test
  def setup
    @agent = Object.new
  end

  def test_event_base_class
    event = Strands::Hooks::Event.new
    refute event.reverse_callbacks?
  end

  def test_agent_event_stores_agent
    event = Strands::Hooks::AgentEvent.new(agent: @agent)
    assert_equal @agent, event.agent
  end

  def test_agent_initialized_event
    event = Strands::Hooks::AgentInitializedEvent.new(agent: @agent)
    assert_kind_of Strands::Hooks::AgentEvent, event
    assert_equal @agent, event.agent
  end

  def test_before_invocation_event
    event = Strands::Hooks::BeforeInvocationEvent.new(
      agent: @agent,
      invocation_state: { key: "val" },
      messages: [{ role: "user" }]
    )
    assert_equal @agent, event.agent
    assert_equal({ key: "val" }, event.invocation_state)
    assert_equal([{ role: "user" }], event.messages)
    assert_equal false, event.cancel
    refute event.reverse_callbacks?
  end

  def test_before_invocation_event_mutable
    event = Strands::Hooks::BeforeInvocationEvent.new(agent: @agent)
    event.cancel = "cancelled"
    event.messages = [{ role: "assistant" }]
    assert_equal "cancelled", event.cancel
    assert_equal [{ role: "assistant" }], event.messages
  end

  def test_after_invocation_event_reverses
    event = Strands::Hooks::AfterInvocationEvent.new(agent: @agent, result: "done")
    assert_equal "done", event.result
    assert_nil event.resume
    assert event.reverse_callbacks?
  end

  def test_after_invocation_event_resume
    event = Strands::Hooks::AfterInvocationEvent.new(agent: @agent)
    event.resume = "continue"
    assert_equal "continue", event.resume
  end

  def test_message_added_event
    msg = { role: "user", content: "hi" }
    event = Strands::Hooks::MessageAddedEvent.new(agent: @agent, message: msg)
    assert_equal msg, event.message
  end

  def test_before_tool_call_event
    tool = Object.new
    event = Strands::Hooks::BeforeToolCallEvent.new(
      agent: @agent, selected_tool: tool, tool_use: { name: "calc" }
    )
    assert_equal tool, event.selected_tool
    assert_equal({ name: "calc" }, event.tool_use)
    assert_equal false, event.cancel_tool
  end

  def test_before_tool_call_event_mutable
    event = Strands::Hooks::BeforeToolCallEvent.new(
      agent: @agent, selected_tool: nil, tool_use: {}
    )
    event.cancel_tool = "denied"
    event.selected_tool = "new_tool"
    assert_equal "denied", event.cancel_tool
    assert_equal "new_tool", event.selected_tool
  end

  def test_after_tool_call_event
    event = Strands::Hooks::AfterToolCallEvent.new(
      agent: @agent, selected_tool: nil, tool_use: {},
      result: "42", exception: RuntimeError.new("oops")
    )
    assert_equal "42", event.result
    assert_kind_of RuntimeError, event.exception
    assert_equal false, event.retry
    assert event.reverse_callbacks?
  end

  def test_before_model_call_event
    event = Strands::Hooks::BeforeModelCallEvent.new(agent: @agent)
    assert_equal false, event.cancel
    refute event.reverse_callbacks?
  end

  def test_after_model_call_event
    event = Strands::Hooks::AfterModelCallEvent.new(
      agent: @agent, stop_reason: "end_turn",
      message: { role: "assistant" }
    )
    assert_equal "end_turn", event.stop_reason
    assert_equal({ role: "assistant" }, event.message)
    assert_equal false, event.retry
    assert event.reverse_callbacks?
  end
end

# ============================================================
# Hooks Registry Tests
# ============================================================
class TestHooksRegistry < Minitest::Test
  def setup
    @registry = Strands::Hooks::Registry.new
    @agent = Object.new
  end

  def test_add_callback_and_fire
    called = false
    @registry.add_callback(Strands::Hooks::BeforeModelCallEvent) { |_e| called = true }
    event = Strands::Hooks::BeforeModelCallEvent.new(agent: @agent)
    @registry.fire(event)
    assert called
  end

  def test_add_callback_requires_block
    assert_raises(ArgumentError) { @registry.add_callback(Strands::Hooks::BeforeModelCallEvent) }
  end

  def test_add_callback_requires_class
    assert_raises(ArgumentError) { @registry.add_callback("not a class") { |_e| } }
  end

  def test_fires_callbacks_in_priority_order
    results = []
    @registry.add_callback(Strands::Hooks::BeforeModelCallEvent, order: 50) { |_e| results << "after" }
    @registry.add_callback(Strands::Hooks::BeforeModelCallEvent, order: -50) { |_e| results << "before" }
    @registry.add_callback(Strands::Hooks::BeforeModelCallEvent, order: 0) { |_e| results << "normal" }

    event = Strands::Hooks::BeforeModelCallEvent.new(agent: @agent)
    @registry.fire(event)
    assert_equal %w[before normal after], results
  end

  def test_preserves_registration_order_within_same_priority
    results = []
    @registry.add_callback(Strands::Hooks::BeforeModelCallEvent) { |_e| results << "first" }
    @registry.add_callback(Strands::Hooks::BeforeModelCallEvent) { |_e| results << "second" }
    @registry.add_callback(Strands::Hooks::BeforeModelCallEvent) { |_e| results << "third" }

    event = Strands::Hooks::BeforeModelCallEvent.new(agent: @agent)
    @registry.fire(event)
    assert_equal %w[first second third], results
  end

  def test_reverse_callbacks_for_after_events
    results = []
    @registry.add_callback(Strands::Hooks::AfterModelCallEvent) { |_e| results << "first" }
    @registry.add_callback(Strands::Hooks::AfterModelCallEvent) { |_e| results << "second" }
    @registry.add_callback(Strands::Hooks::AfterModelCallEvent) { |_e| results << "third" }

    event = Strands::Hooks::AfterModelCallEvent.new(agent: @agent)
    @registry.fire(event)
    assert_equal %w[third second first], results
  end

  def test_reverse_respects_priority_groups
    results = []
    @registry.add_callback(Strands::Hooks::AfterModelCallEvent, order: 10) { |_e| results << "high" }
    @registry.add_callback(Strands::Hooks::AfterModelCallEvent, order: -10) { |_e| results << "low1" }
    @registry.add_callback(Strands::Hooks::AfterModelCallEvent, order: -10) { |_e| results << "low2" }

    event = Strands::Hooks::AfterModelCallEvent.new(agent: @agent)
    @registry.fire(event)
    assert_equal %w[low2 low1 high], results
  end

  def test_fires_only_matching_event_type
    results = []
    @registry.add_callback(Strands::Hooks::BeforeModelCallEvent) { |_e| results << "model" }
    @registry.add_callback(Strands::Hooks::BeforeToolCallEvent) { |_e| results << "tool" }

    event = Strands::Hooks::BeforeModelCallEvent.new(agent: @agent)
    @registry.fire(event)
    assert_equal ["model"], results
  end

  def test_add_hook_from_provider
    provider = Object.new
    def provider.register_hooks(reg)
      reg.add_callback(Strands::Hooks::BeforeModelCallEvent) { |_e| }
    end
    @registry.add_hook(provider)
    assert_equal 1, @registry.callback_count(Strands::Hooks::BeforeModelCallEvent)
  end

  def test_add_hook_raises_for_non_provider
    assert_raises(ArgumentError) { @registry.add_hook(Object.new) }
  end

  def test_callbacks_predicate
    refute @registry.callbacks?
    @registry.add_callback(Strands::Hooks::BeforeModelCallEvent) { |_e| }
    assert @registry.callbacks?
  end

  def test_callbacks_for
    cb = proc { |_e| }
    @registry.add_callback(Strands::Hooks::BeforeModelCallEvent, &cb)
    assert_equal [cb], @registry.callbacks_for(Strands::Hooks::BeforeModelCallEvent)
    assert_equal [], @registry.callbacks_for(Strands::Hooks::AfterModelCallEvent)
  end
end

# ============================================================
# Interventions Actions Tests
# ============================================================
class TestInterventionActions < Minitest::Test
  def test_proceed
    action = Strands::Interventions::Proceed.new
    assert_equal "proceed", action.type
    assert_nil action.reason
  end

  def test_proceed_with_reason
    action = Strands::Interventions::Proceed.new(reason: "all good")
    assert_equal "all good", action.reason
  end

  def test_deny
    action = Strands::Interventions::Deny.new(reason: "not allowed")
    assert_equal "deny", action.type
    assert_equal "not allowed", action.reason
  end

  def test_guide
    action = Strands::Interventions::Guide.new(feedback: "try this", reason: "help")
    assert_equal "guide", action.type
    assert_equal "try this", action.feedback
    assert_equal "help", action.reason
  end

  def test_transform
    transform_fn = ->(event) { event.result = "modified" }
    action = Strands::Interventions::Transform.new(apply: transform_fn, reason: "needed")
    assert_equal "transform", action.type
    assert_equal transform_fn, action.apply
    assert_equal "needed", action.reason
  end

  def test_equality
    assert_equal Strands::Interventions::Proceed.new, Strands::Interventions::Proceed.new
    assert_equal Strands::Interventions::Deny.new(reason: "x"), Strands::Interventions::Deny.new(reason: "x")
    refute_equal Strands::Interventions::Deny.new(reason: "x"), Strands::Interventions::Deny.new(reason: "y")
    refute_equal Strands::Interventions::Proceed.new, Strands::Interventions::Deny.new
  end
end

# ============================================================
# Interventions Handler Tests
# ============================================================
class TestInterventionHandler < Minitest::Test
  def test_abstract_name
    handler = Strands::Interventions::Handler.new
    assert_raises(NotImplementedError) { handler.name }
  end

  def test_default_on_error
    handler = Strands::Interventions::Handler.new
    assert_equal :throw, handler.on_error
  end

  def test_default_lifecycle_methods_return_proceed
    handler = Strands::Interventions::Handler.new
    assert_kind_of Strands::Interventions::Proceed, handler.before_invocation(nil)
    assert_kind_of Strands::Interventions::Proceed, handler.before_tool_call(nil)
    assert_kind_of Strands::Interventions::Proceed, handler.after_tool_call(nil)
    assert_kind_of Strands::Interventions::Proceed, handler.before_model_call(nil)
    assert_kind_of Strands::Interventions::Proceed, handler.after_model_call(nil)
  end

  def test_custom_handler
    klass = Class.new(Strands::Interventions::Handler) do
      define_method(:name) { "custom" }
      define_method(:before_tool_call) { |event| Strands::Interventions::Deny.new(reason: "blocked") }
    end

    handler = klass.new
    assert_equal "custom", handler.name
    result = handler.before_tool_call(nil)
    assert_kind_of Strands::Interventions::Deny, result
    assert_equal "blocked", result.reason

    # Non-overridden still returns Proceed
    assert_kind_of Strands::Interventions::Proceed, handler.before_model_call(nil)
  end
end

# ============================================================
# Interventions Registry Tests
# ============================================================
class TestInterventionRegistry < Minitest::Test
  def setup
    @agent = Object.new
    @hook_registry = Strands::Hooks::Registry.new
  end

  def test_duplicate_names_raise
    handler1 = create_handler("same")
    handler2 = create_handler("same")
    assert_raises(ArgumentError) do
      Strands::Interventions::Registry.new(handlers: [handler1, handler2], hook_registry: @hook_registry)
    end
  end

  def test_deny_short_circuits_before_tool_call
    deny_handler = create_handler("deny-all") do
      define_method(:before_tool_call) { |event| Strands::Interventions::Deny.new(reason: "nope") }
    end
    never_handler = create_handler("never") do
      define_method(:before_tool_call) { |event| raise "should not be called" }
    end

    Strands::Interventions::Registry.new(handlers: [deny_handler, never_handler], hook_registry: @hook_registry)

    event = Strands::Hooks::BeforeToolCallEvent.new(
      agent: @agent, selected_tool: nil, tool_use: {}
    )
    @hook_registry.fire(event)
    assert_equal "DENIED: nope", event.cancel_tool
  end

  def test_deny_short_circuits_before_invocation
    handler = create_handler("deny-invoke") do
      define_method(:before_invocation) { |event| Strands::Interventions::Deny.new(reason: "stop") }
    end

    Strands::Interventions::Registry.new(handlers: [handler], hook_registry: @hook_registry)

    event = Strands::Hooks::BeforeInvocationEvent.new(agent: @agent)
    @hook_registry.fire(event)
    assert_equal "DENIED: stop", event.cancel
  end

  def test_guide_accumulation
    g1 = create_handler("guide-1") do
      define_method(:before_invocation) { |event| Strands::Interventions::Guide.new(feedback: "tip 1") }
    end
    g2 = create_handler("guide-2") do
      define_method(:before_invocation) { |event| Strands::Interventions::Guide.new(feedback: "tip 2") }
    end

    Strands::Interventions::Registry.new(handlers: [g1, g2], hook_registry: @hook_registry)

    event = Strands::Hooks::BeforeInvocationEvent.new(agent: @agent)
    @hook_registry.fire(event)
    assert_includes event.cancel, "[guide-1] tip 1"
    assert_includes event.cancel, "[guide-2] tip 2"
  end

  def test_transform_applies
    handler = create_handler("transform") do
      define_method(:before_tool_call) do |event|
        Strands::Interventions::Transform.new(
          apply: ->(e) { e.tool_use = { name: "transformed" } }
        )
      end
    end

    Strands::Interventions::Registry.new(handlers: [handler], hook_registry: @hook_registry)

    event = Strands::Hooks::BeforeToolCallEvent.new(
      agent: @agent, selected_tool: nil, tool_use: { name: "original" }
    )
    @hook_registry.fire(event)
    assert_equal({ name: "transformed" }, event.tool_use)
  end

  def test_after_model_call_guide_sets_retry
    handler = create_handler("retry") do
      define_method(:after_model_call) { |event| Strands::Interventions::Guide.new(feedback: "retry") }
    end

    Strands::Interventions::Registry.new(handlers: [handler], hook_registry: @hook_registry)

    event = Strands::Hooks::AfterModelCallEvent.new(agent: @agent)
    @hook_registry.fire(event)
    assert event.retry
  end

  def test_error_handling_throw
    handler = create_handler("throws") do
      define_method(:before_tool_call) { |event| raise "boom" }
    end

    Strands::Interventions::Registry.new(handlers: [handler], hook_registry: @hook_registry)

    event = Strands::Hooks::BeforeToolCallEvent.new(
      agent: @agent, selected_tool: nil, tool_use: {}
    )
    assert_raises(RuntimeError) { @hook_registry.fire(event) }
  end

  def test_error_handling_deny
    handler = create_handler("deny-err") do
      define_method(:on_error) { :deny }
      define_method(:before_tool_call) { |event| raise "broken" }
    end

    Strands::Interventions::Registry.new(handlers: [handler], hook_registry: @hook_registry)

    event = Strands::Hooks::BeforeToolCallEvent.new(
      agent: @agent, selected_tool: nil, tool_use: {}
    )
    @hook_registry.fire(event)
    assert_equal "DENIED: Handler threw: broken", event.cancel_tool
  end

  def test_error_handling_proceed
    handler = create_handler("proceed-err") do
      define_method(:on_error) { :proceed }
      define_method(:before_tool_call) { |event| raise "ignored" }
    end

    Strands::Interventions::Registry.new(handlers: [handler], hook_registry: @hook_registry)

    event = Strands::Hooks::BeforeToolCallEvent.new(
      agent: @agent, selected_tool: nil, tool_use: {}
    )
    @hook_registry.fire(event)
    assert_equal false, event.cancel_tool
  end

  def test_only_overridden_methods_hooked
    handler = create_handler("partial") do
      define_method(:before_tool_call) { |event| Strands::Interventions::Proceed.new }
    end

    Strands::Interventions::Registry.new(handlers: [handler], hook_registry: @hook_registry)

    assert_equal 0, @hook_registry.callback_count(Strands::Hooks::BeforeModelCallEvent)
    assert_equal 1, @hook_registry.callback_count(Strands::Hooks::BeforeToolCallEvent)
  end

  def test_handler_evaluation_order
    order = []
    h1 = create_handler("h1") do
      define_method(:before_tool_call) do |event|
        order << "h1"
        Strands::Interventions::Proceed.new
      end
    end
    h2 = create_handler("h2") do
      define_method(:before_tool_call) do |event|
        order << "h2"
        Strands::Interventions::Proceed.new
      end
    end

    Strands::Interventions::Registry.new(handlers: [h1, h2], hook_registry: @hook_registry)

    event = Strands::Hooks::BeforeToolCallEvent.new(
      agent: @agent, selected_tool: nil, tool_use: {}
    )
    @hook_registry.fire(event)
    assert_equal %w[h1 h2], order
  end

  private

  def create_handler(name, &block)
    klass = Class.new(Strands::Interventions::Handler) do
      define_method(:name) { name }
    end
    klass.class_eval(&block) if block
    klass.new
  end
end

# ============================================================
# Plugins Base Tests
# ============================================================
class TestPluginsBase < Minitest::Test
  def setup
    @agent = Object.new
  end

  def test_plugin_name
    klass = Class.new do
      include Strands::Plugins::Base
      plugin_name "my-plugin"
    end
    plugin = klass.new
    assert_equal "my-plugin", plugin.name
  end

  def test_hook_declaration_and_discovery
    klass = Class.new do
      include Strands::Plugins::Base
      plugin_name "hook-plugin"

      hook :on_model, event: Strands::Hooks::BeforeModelCallEvent
      def on_model(event)
        "called"
      end
    end

    plugin = klass.new
    hooks = plugin.hooks
    assert_equal 1, hooks.length
    assert_equal Strands::Hooks::BeforeModelCallEvent, hooks.first[:event]
    assert_equal Strands::Hooks::HookOrder::DEFAULT, hooks.first[:order]
    assert_equal "called", hooks.first[:callback].call(nil)
  end

  def test_tool_declaration_and_discovery
    klass = Class.new do
      include Strands::Plugins::Base
      plugin_name "tool-plugin"

      plugin_tool :calc, description: "Calculator", schema: { type: "object" }
      def calc(params)
        params[:a] + params[:b]
      end
    end

    plugin = klass.new
    tools = plugin.tools
    assert_equal 1, tools.length
    assert_equal "calc", tools.first[:name]
    assert_equal "Calculator", tools.first[:description]
    assert_equal({ type: "object" }, tools.first[:schema])
  end

  def test_register_hooks_with_registry
    klass = Class.new do
      include Strands::Plugins::Base
      plugin_name "registerable"

      hook :on_model, event: Strands::Hooks::BeforeModelCallEvent
      def on_model(event)
      end
    end

    plugin = klass.new
    registry = Strands::Hooks::Registry.new
    plugin.register_hooks(registry)
    assert_equal 1, registry.callback_count(Strands::Hooks::BeforeModelCallEvent)
  end

  def test_registered_hooks_invoke_plugin_method
    called_with = nil
    klass = Class.new do
      include Strands::Plugins::Base
      plugin_name "callable"

      hook :on_model, event: Strands::Hooks::BeforeModelCallEvent
      define_method(:on_model) { |event| called_with = event }
    end

    plugin = klass.new
    registry = Strands::Hooks::Registry.new
    plugin.register_hooks(registry)

    event = Strands::Hooks::BeforeModelCallEvent.new(agent: @agent)
    registry.fire(event)
    assert_equal event, called_with
  end

  def test_inheritance_hooks
    parent = Class.new do
      include Strands::Plugins::Base
      plugin_name "parent"

      hook :parent_hook, event: Strands::Hooks::BeforeModelCallEvent
      def parent_hook(event)
      end
    end

    child = Class.new(parent) do
      hook :child_hook, event: Strands::Hooks::BeforeToolCallEvent
      def child_hook(event)
      end
    end

    plugin = child.new
    assert_equal 2, plugin.hooks.length
  end

  def test_inheritance_tools
    parent = Class.new do
      include Strands::Plugins::Base
      plugin_name "parent-tools"

      plugin_tool :parent_tool, description: "parent"
      def parent_tool(p)
      end
    end

    child = Class.new(parent) do
      plugin_tool :child_tool, description: "child"
      def child_tool(p)
      end
    end

    plugin = child.new
    assert_equal 2, plugin.tools.length
  end

  def test_child_override_replaces_parent_hook
    parent = Class.new do
      include Strands::Plugins::Base
      plugin_name "override"

      hook :shared, event: Strands::Hooks::BeforeModelCallEvent
      def shared(event)
        "parent"
      end
    end

    child = Class.new(parent) do
      def shared(event)
        "child"
      end
    end

    plugin = child.new
    hooks = plugin.hooks
    assert_equal 1, hooks.length
    assert_equal "child", hooks.first[:callback].call(nil)
  end

  def test_init_agent_default_noop
    klass = Class.new do
      include Strands::Plugins::Base
      plugin_name "noop"
    end
    plugin = klass.new
    assert_nil plugin.init_agent(@agent)
  end

  def test_multiple_hooks_on_same_event
    klass = Class.new do
      include Strands::Plugins::Base
      plugin_name "multi"

      hook :hook1, event: Strands::Hooks::BeforeModelCallEvent, order: -10
      def hook1(event)
      end

      hook :hook2, event: Strands::Hooks::BeforeModelCallEvent, order: 10
      def hook2(event)
      end
    end

    plugin = klass.new
    hooks = plugin.hooks
    assert_equal 2, hooks.length
  end
end
