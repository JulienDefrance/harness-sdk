# frozen_string_literal: true

require "spec_helper"

RSpec.describe Strands::Tools::Definition do
  describe "#initialize" do
    it "creates a definition with all required fields" do
      definition = described_class.new(
        name: "test_tool",
        description: "A test tool",
        input_schema: { properties: { x: { type: "string" } } },
        callable: -> { "result" }
      )

      expect(definition.name).to eq("test_tool")
      expect(definition.description).to eq("A test tool")
      expect(definition.callable).to respond_to(:call)
    end

    it "normalizes the input schema" do
      definition = described_class.new(
        name: "test",
        description: "Test",
        input_schema: { properties: { x: { type: "integer" } }, required: ["x"] },
        callable: -> { nil }
      )

      expect(definition.input_schema["type"]).to eq("object")
      expect(definition.input_schema["properties"]).to have_key("x")
      expect(definition.input_schema["required"]).to eq(["x"])
    end

    it "provides default values for missing schema fields" do
      definition = described_class.new(
        name: "test",
        description: "Test",
        input_schema: {},
        callable: -> { nil }
      )

      expect(definition.input_schema["type"]).to eq("object")
      expect(definition.input_schema["properties"]).to eq({})
      expect(definition.input_schema["required"]).to eq([])
    end

    it "adds default description to properties missing one" do
      definition = described_class.new(
        name: "test",
        description: "Test",
        input_schema: { properties: { x: { type: "string" } } },
        callable: -> { nil }
      )

      expect(definition.input_schema["properties"]["x"]["description"]).to eq("Parameter x")
    end

    it "raises ArgumentError for empty name" do
      expect {
        described_class.new(name: "", description: "Test", input_schema: {}, callable: -> { nil })
      }.to raise_error(ArgumentError, /name cannot be empty/)
    end

    it "raises ArgumentError for empty description" do
      expect {
        described_class.new(name: "test", description: "", input_schema: {}, callable: -> { nil })
      }.to raise_error(ArgumentError, /description cannot be empty/)
    end

    it "raises ArgumentError if callable does not respond to #call" do
      expect {
        described_class.new(name: "test", description: "Test", input_schema: {}, callable: "not_callable")
      }.to raise_error(ArgumentError, /callable must respond to #call/)
    end
  end

  describe ".from_block" do
    it "creates a definition from a block" do
      definition = described_class.from_block(
        name: "greet",
        description: "Greets someone",
        schema: { properties: { name: { type: "string" } }, required: ["name"] }
      ) { |name:| "Hello, #{name}!" }

      expect(definition.name).to eq("greet")
      expect(definition.description).to eq("Greets someone")
      expect(definition.call({ "name" => "World" })).to eq("Hello, World!")
    end

    it "raises ArgumentError without a block" do
      expect {
        described_class.from_block(name: "test", description: "Test")
      }.to raise_error(ArgumentError, /block is required/)
    end

    it "uses empty schema by default" do
      definition = described_class.from_block(
        name: "noop",
        description: "Does nothing"
      ) { "done" }

      expect(definition.input_schema["properties"]).to eq({})
    end
  end

  describe "#call" do
    it "invokes the callable with symbolized input keys" do
      definition = described_class.new(
        name: "adder",
        description: "Adds two numbers",
        input_schema: {},
        callable: ->(x:, y:) { x + y }
      )

      expect(definition.call({ "x" => 3, "y" => 4 })).to eq(7)
    end

    it "works with symbol keys in input" do
      definition = described_class.new(
        name: "echo",
        description: "Echoes",
        input_schema: {},
        callable: ->(message:) { message }
      )

      expect(definition.call({ message: "hello" })).to eq("hello")
    end

    it "passes tool_context when callable accepts it" do
      received_context = nil
      definition = described_class.new(
        name: "ctx_tool",
        description: "Uses context",
        input_schema: {},
        callable: ->(tool_context:) { received_context = tool_context; "ok" }
      )

      tool_use = Strands::Types::Tools::ToolUse.new(
        name: "ctx_tool", tool_use_id: "abc", input: {}
      )
      context = Strands::Tools::ToolContext.new(tool_use: tool_use, agent: nil)

      definition.call({}, context: context)
      expect(received_context).to eq(context)
    end

    it "does not inject context when callable does not accept it" do
      definition = described_class.new(
        name: "simple",
        description: "Simple",
        input_schema: {},
        callable: -> { "no context needed" }
      )

      tool_use = Strands::Types::Tools::ToolUse.new(
        name: "simple", tool_use_id: "abc", input: {}
      )
      context = Strands::Tools::ToolContext.new(tool_use: tool_use, agent: nil)

      expect(definition.call({}, context: context)).to eq("no context needed")
    end

    it "works with no arguments" do
      definition = described_class.new(
        name: "constant",
        description: "Returns a constant",
        input_schema: {},
        callable: -> { 42 }
      )

      expect(definition.call).to eq(42)
    end
  end

  describe "#tool_spec" do
    it "returns a ToolSpec struct" do
      definition = described_class.new(
        name: "my_tool",
        description: "Does something",
        input_schema: { properties: { x: { type: "string" } } },
        callable: -> { nil }
      )

      spec = definition.tool_spec
      expect(spec).to be_a(Strands::Types::Tools::ToolSpec)
      expect(spec.name).to eq("my_tool")
      expect(spec.description).to eq("Does something")
      expect(spec.input_schema["properties"]).to have_key("x")
    end
  end

  describe "#to_h" do
    it "returns a hash representation" do
      definition = described_class.new(
        name: "test",
        description: "Test tool",
        input_schema: {},
        callable: -> { nil }
      )

      h = definition.to_h
      expect(h[:name]).to eq("test")
      expect(h[:description]).to eq("Test tool")
      expect(h[:input_schema]).to be_a(Hash)
    end
  end
end
