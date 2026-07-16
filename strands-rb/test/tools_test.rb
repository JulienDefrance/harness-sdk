# frozen_string_literal: true

# Minitest-based verification for the Tools system.
# This runs the same test cases as the RSpec specs under spec/strands/tools/
# Used for verification in environments where RSpec is not available.

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "strands"
require "minitest/autorun"

class DefinitionTest < Minitest::Test
  def test_creates_with_all_fields
    defn = Strands::Tools::Definition.new(
      name: "test_tool",
      description: "A test tool",
      input_schema: { properties: { x: { type: "string" } } },
      callable: -> { "result" }
    )

    assert_equal "test_tool", defn.name
    assert_equal "A test tool", defn.description
    assert defn.callable.respond_to?(:call)
  end

  def test_normalizes_schema
    defn = Strands::Tools::Definition.new(
      name: "test", description: "T",
      input_schema: { properties: { x: { type: "integer" } }, required: ["x"] },
      callable: -> { nil }
    )

    assert_equal "object", defn.input_schema["type"]
    assert defn.input_schema["properties"].key?("x")
    assert_equal ["x"], defn.input_schema["required"]
  end

  def test_defaults_for_empty_schema
    defn = Strands::Tools::Definition.new(
      name: "test", description: "T", input_schema: {}, callable: -> { nil }
    )

    assert_equal "object", defn.input_schema["type"]
    assert_equal({}, defn.input_schema["properties"])
    assert_equal [], defn.input_schema["required"]
  end

  def test_adds_default_description_to_properties
    defn = Strands::Tools::Definition.new(
      name: "test", description: "T",
      input_schema: { properties: { x: { type: "string" } } },
      callable: -> { nil }
    )

    assert_equal "Parameter x", defn.input_schema["properties"]["x"]["description"]
  end

  def test_raises_for_empty_name
    assert_raises(ArgumentError) do
      Strands::Tools::Definition.new(name: "", description: "T", input_schema: {}, callable: -> { nil })
    end
  end

  def test_raises_for_empty_description
    assert_raises(ArgumentError) do
      Strands::Tools::Definition.new(name: "test", description: "", input_schema: {}, callable: -> { nil })
    end
  end

  def test_raises_for_non_callable
    assert_raises(ArgumentError) do
      Strands::Tools::Definition.new(name: "test", description: "T", input_schema: {}, callable: "nope")
    end
  end

  def test_from_block
    defn = Strands::Tools::Definition.from_block(
      name: "greet", description: "Greets",
      schema: { properties: { name: { type: "string" } }, required: ["name"] }
    ) { |name:| "Hello, #{name}!" }

    assert_equal "greet", defn.name
    assert_equal "Hello, World!", defn.call({ "name" => "World" })
  end

  def test_from_block_raises_without_block
    assert_raises(ArgumentError) do
      Strands::Tools::Definition.from_block(name: "test", description: "Test")
    end
  end

  def test_call_with_string_keys
    defn = Strands::Tools::Definition.new(
      name: "adder", description: "Adds",
      input_schema: {},
      callable: ->(x:, y:) { x + y }
    )

    assert_equal 7, defn.call({ "x" => 3, "y" => 4 })
  end

  def test_call_with_symbol_keys
    defn = Strands::Tools::Definition.new(
      name: "echo", description: "Echoes",
      input_schema: {},
      callable: ->(message:) { message }
    )

    assert_equal "hello", defn.call({ message: "hello" })
  end

  def test_call_passes_tool_context
    received = nil
    defn = Strands::Tools::Definition.new(
      name: "ctx_tool", description: "Uses context",
      input_schema: {},
      callable: ->(tool_context:) { received = tool_context; "ok" }
    )

    tool_use = Strands::Types::Tools::ToolUse.new(name: "ctx_tool", tool_use_id: "abc", input: {})
    ctx = Strands::Tools::ToolContext.new(tool_use: tool_use, agent: nil)
    defn.call({}, context: ctx)

    assert_equal ctx, received
  end

  def test_call_no_args
    defn = Strands::Tools::Definition.new(
      name: "const", description: "Constant",
      input_schema: {},
      callable: -> { 42 }
    )

    assert_equal 42, defn.call
  end

  def test_tool_spec
    defn = Strands::Tools::Definition.new(
      name: "my_tool", description: "Does stuff",
      input_schema: { properties: { x: { type: "string" } } },
      callable: -> { nil }
    )

    spec = defn.tool_spec
    assert_kind_of Strands::Types::Tools::ToolSpec, spec
    assert_equal "my_tool", spec.name
    assert_equal "Does stuff", spec.description
  end

  def test_to_h
    defn = Strands::Tools::Definition.new(
      name: "test", description: "Test tool",
      input_schema: {}, callable: -> { nil }
    )

    h = defn.to_h
    assert_equal "test", h[:name]
    assert_equal "Test tool", h[:description]
    assert_kind_of Hash, h[:input_schema]
  end
end

class RegistryTest < Minitest::Test
  def setup
    @registry = Strands::Tools::Registry.new
    @calculator = Strands::Tools::Definition.new(
      name: "calculator", description: "Math",
      input_schema: { properties: { expression: { type: "string" } }, required: ["expression"] },
      callable: ->(expression:) { eval(expression).to_s }
    )
    @greeter = Strands::Tools::Definition.new(
      name: "greeter", description: "Hello",
      input_schema: { properties: { name: { type: "string" } }, required: ["name"] },
      callable: ->(name:) { "Hello, #{name}!" }
    )
  end

  def test_register
    @registry.register(@calculator)
    assert_equal 1, @registry.size
  end

  def test_raises_for_duplicate
    @registry.register(@calculator)
    assert_raises(ArgumentError) { @registry.register(@calculator) }
  end

  def test_raises_for_dash_underscore_conflict
    dash = Strands::Tools::Definition.new(name: "my-tool", description: "D", input_schema: {}, callable: -> { nil })
    under = Strands::Tools::Definition.new(name: "my_tool", description: "U", input_schema: {}, callable: -> { nil })
    @registry.register(dash)
    assert_raises(ArgumentError) { @registry.register(under) }
  end

  def test_get
    @registry.register(@calculator)
    assert_equal @calculator, @registry.get("calculator")
    assert_nil @registry.get("nonexistent")
  end

  def test_fetch
    @registry.register(@calculator)
    assert_equal @calculator, @registry.fetch("calculator")
    assert_raises(KeyError) { @registry.fetch("nonexistent") }
  end

  def test_list
    @registry.register(@calculator)
    @registry.register(@greeter)
    assert_includes @registry.list, "calculator"
    assert_includes @registry.list, "greeter"
  end

  def test_registered?
    @registry.register(@calculator)
    assert @registry.registered?("calculator")
    refute @registry.registered?("unknown")
  end

  def test_tool_specs
    @registry.register(@calculator)
    @registry.register(@greeter)
    specs = @registry.tool_specs
    assert_equal 2, specs.length
    assert specs.all? { |s| s.is_a?(Strands::Types::Tools::ToolSpec) }
  end

  def test_unregister
    @registry.register(@calculator)
    removed = @registry.unregister("calculator")
    assert_equal @calculator, removed
    refute @registry.registered?("calculator")
  end

  def test_process_tools
    names = @registry.process_tools([@calculator, @greeter])
    assert_equal 2, names.length
    assert_includes names, "calculator"
    assert_includes names, "greeter"
  end

  def test_process_tools_with_hash
    names = @registry.process_tools([
      { name: "inline", description: "Inline", input_schema: {}, callable: -> { "ok" } }
    ])
    assert_equal ["inline"], names
  end

  def test_clear
    @registry.register(@calculator)
    @registry.clear
    assert_equal 0, @registry.size
  end

  def test_register_object
    tool_obj = Object.new
    def tool_obj.name = "obj_tool"
    def tool_obj.description = "Object tool"
    def tool_obj.input_schema = {}
    def tool_obj.call(**_) = "obj result"

    @registry.register(tool_obj)
    assert @registry.registered?("obj_tool")
  end
end

class ExecutorTest < Minitest::Test
  def setup
    @registry = Strands::Tools::Registry.new
    @registry.register(Strands::Tools::Definition.new(
      name: "calculator", description: "Math",
      input_schema: { properties: { expression: { type: "string" } } },
      callable: ->(expression:) { eval(expression).to_s }
    ))
    @registry.register(Strands::Tools::Definition.new(
      name: "failing", description: "Fails",
      input_schema: {},
      callable: -> { raise RuntimeError, "Boom" }
    ))
    @registry.register(Strands::Tools::Definition.new(
      name: "hash_tool", description: "Hash",
      input_schema: {},
      callable: -> { { result: "data", count: 42 } }
    ))
    @registry.register(Strands::Tools::Definition.new(
      name: "nil_tool", description: "Nil",
      input_schema: {},
      callable: -> { nil }
    ))
    @executor = Strands::Tools::Executor.new(@registry)
  end

  def test_successful_execution
    tool_use = Strands::Types::Tools::ToolUse.new(
      name: "calculator", tool_use_id: "001", input: { "expression" => "2+3" }
    )
    result = @executor.execute(tool_use)
    assert_equal :success, result.status
    assert_equal "001", result.tool_use_id
    assert_equal "5", result.content.first.text
  end

  def test_tool_not_found
    tool_use = Strands::Types::Tools::ToolUse.new(
      name: "nonexistent", tool_use_id: "002", input: {}
    )
    result = @executor.execute(tool_use)
    assert_equal :error, result.status
    assert_includes result.content.first.text, "not found"
  end

  def test_tool_exception_returns_error
    tool_use = Strands::Types::Tools::ToolUse.new(
      name: "failing", tool_use_id: "003", input: {}
    )
    result = @executor.execute(tool_use)
    assert_equal :error, result.status
    assert_includes result.content.first.text, "RuntimeError"
    assert_includes result.content.first.text, "Boom"
  end

  def test_hash_result
    tool_use = Strands::Types::Tools::ToolUse.new(
      name: "hash_tool", tool_use_id: "004", input: {}
    )
    result = @executor.execute(tool_use)
    assert_equal :success, result.status
    assert_equal({ result: "data", count: 42 }, result.content.first.json)
  end

  def test_nil_result
    tool_use = Strands::Types::Tools::ToolUse.new(
      name: "nil_tool", tool_use_id: "005", input: {}
    )
    result = @executor.execute(tool_use)
    assert_equal :success, result.status
    assert_equal "", result.content.first.text
  end

  def test_with_agent_context
    @registry.register(Strands::Tools::Definition.new(
      name: "context_tool", description: "Context",
      input_schema: {},
      callable: ->(tool_context:) { "agent=#{tool_context.agent}" }
    ))
    tool_use = Strands::Types::Tools::ToolUse.new(
      name: "context_tool", tool_use_id: "006", input: {}
    )
    result = @executor.execute(tool_use, agent: "test_agent")
    assert_equal :success, result.status
    assert_includes result.content.first.text, "test_agent"
  end

  def test_nil_input
    @registry.register(Strands::Tools::Definition.new(
      name: "no_input", description: "No input",
      input_schema: {},
      callable: -> { "done" }
    ))
    tool_use = Strands::Types::Tools::ToolUse.new(
      name: "no_input", tool_use_id: "007", input: nil
    )
    result = @executor.execute(tool_use)
    assert_equal :success, result.status
    assert_equal "done", result.content.first.text
  end
end

class DSLTest < Minitest::Test
  def test_define_tool_with_block
    defn = Strands::Tools::DSL.define_tool(
      "reverse", description: "Reverses text",
      schema: { properties: { text: { type: "string" } }, required: ["text"] }
    ) { |text:| text.reverse }

    assert_kind_of Strands::Tools::Definition, defn
    assert_equal "reverse", defn.name
    assert_equal "olleh", defn.call({ "text" => "hello" })
  end

  def test_define_tool_with_callable
    impl = ->(x:, y:) { x.to_i + y.to_i }
    defn = Strands::Tools::DSL.define_tool("add", description: "Adds", callable: impl)
    assert_equal 8, defn.call({ "x" => 5, "y" => 3 })
  end

  def test_raises_without_callable_or_block
    assert_raises(ArgumentError) do
      Strands::Tools::DSL.define_tool("broken", description: "No impl")
    end
  end

  def test_strands_tool_method
    tool = Strands.tool("upper", description: "Uppercases",
      schema: { properties: { text: { type: "string" } }, required: ["text"] }
    ) { |text:| text.upcase }

    assert_kind_of Strands::Tools::Definition, tool
    assert_equal "HELLO", tool.call({ "text" => "hello" })
  end

  def test_strands_tool_no_args
    tool = Strands.tool("ping", description: "Pong") { "pong" }
    assert_equal "pong", tool.call
  end

  def test_strands_tool_with_lambda
    impl = ->(a:, b:) { a.to_f / b.to_f }
    tool = Strands.tool("divide", description: "Divides",
      schema: { properties: { a: { type: "number" }, b: { type: "number" } } },
      callable: impl
    )
    assert_equal 5.0, tool.call({ "a" => 10.0, "b" => 2.0 })
  end

  def test_integrates_with_registry
    tool = Strands.tool("reg_tool", description: "Registered") { "registered" }
    registry = Strands::Tools::Registry.new
    registry.register(tool)
    assert_equal "registered", registry.get("reg_tool").call
  end
end

class ToolContextTest < Minitest::Test
  def test_attributes
    tool_use = Strands::Types::Tools::ToolUse.new(
      name: "test", tool_use_id: "ctx-1", input: { "x" => 1 }
    )
    ctx = Strands::Tools::ToolContext.new(
      tool_use: tool_use, agent: "agent_obj", invocation_state: { key: "val" }
    )

    assert_equal tool_use, ctx.tool_use
    assert_equal "agent_obj", ctx.agent
    assert_equal({ key: "val" }, ctx.invocation_state)
  end

  def test_convenience_methods
    tool_use = Strands::Types::Tools::ToolUse.new(
      name: "my_tool", tool_use_id: "ctx-2", input: { "a" => "b" }
    )
    ctx = Strands::Tools::ToolContext.new(tool_use: tool_use)

    assert_equal "ctx-2", ctx.tool_use_id
    assert_equal "my_tool", ctx.tool_name
    assert_equal({ "a" => "b" }, ctx.input)
  end

  def test_defaults
    tool_use = Strands::Types::Tools::ToolUse.new(
      name: "x", tool_use_id: "y", input: {}
    )
    ctx = Strands::Tools::ToolContext.new(tool_use: tool_use)

    assert_nil ctx.agent
    assert_equal({}, ctx.invocation_state)
  end
end
