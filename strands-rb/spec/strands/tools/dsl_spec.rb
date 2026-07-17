# frozen_string_literal: true

require "spec_helper"

RSpec.describe Strands::Tools::DSL do
  describe ".define_tool" do
    it "creates a Definition from a block" do
      definition = described_class.define_tool(
        "reverse",
        description: "Reverses text",
        schema: {
          properties: { text: { type: "string", description: "Text to reverse" } },
          required: ["text"]
        }
      ) { |text:| text.reverse }

      expect(definition).to be_a(Strands::Tools::Definition)
      expect(definition.name).to eq("reverse")
      expect(definition.call({ "text" => "hello" })).to eq("olleh")
    end

    it "creates a Definition from a callable parameter" do
      impl = ->(x:, y:) { x.to_i + y.to_i }

      definition = described_class.define_tool(
        "add",
        description: "Adds numbers",
        schema: { properties: { x: { type: "integer" }, y: { type: "integer" } } },
        callable: impl
      )

      expect(definition.call({ "x" => 5, "y" => 3 })).to eq(8)
    end

    it "raises ArgumentError without callable or block" do
      expect {
        described_class.define_tool("broken", description: "No impl")
      }.to raise_error(ArgumentError, /callable or block is required/)
    end

    it "uses empty schema when none provided" do
      definition = described_class.define_tool("simple", description: "Simple") { "ok" }

      expect(definition.input_schema["properties"]).to eq({})
    end

    it "prefers callable over block when both given" do
      callable = -> { "from callable" }

      definition = described_class.define_tool(
        "test",
        description: "Test",
        callable: callable
      ) { "from block" }

      expect(definition.call).to eq("from callable")
    end
  end

  describe "Strands.tool" do
    it "is available as a module-level method" do
      expect(Strands).to respond_to(:tool)
    end

    it "creates a tool definition with a block" do
      tool = Strands.tool("upper",
        description: "Uppercases text",
        schema: {
          properties: { text: { type: "string" } },
          required: ["text"]
        }
      ) { |text:| text.upcase }

      expect(tool).to be_a(Strands::Tools::Definition)
      expect(tool.name).to eq("upper")
      expect(tool.call({ "text" => "hello" })).to eq("HELLO")
    end

    it "creates a tool definition with a lambda" do
      impl = ->(a:, b:) { a.to_f / b.to_f }

      tool = Strands.tool("divide",
        description: "Divides two numbers",
        schema: {
          properties: { a: { type: "number" }, b: { type: "number" } },
          required: %w[a b]
        },
        callable: impl
      )

      expect(tool.call({ "a" => 10.0, "b" => 2.0 })).to eq(5.0)
    end

    it "generates a valid tool_spec" do
      tool = Strands.tool("test_tool",
        description: "Test description",
        schema: {
          properties: { input: { type: "string", description: "The input" } },
          required: ["input"]
        }
      ) { |input:| input }

      spec = tool.tool_spec
      expect(spec.name).to eq("test_tool")
      expect(spec.description).to eq("Test description")
      expect(spec.input_schema["required"]).to eq(["input"])
    end

    it "works with no-argument tools" do
      tool = Strands.tool("ping", description: "Returns pong") { "pong" }

      expect(tool.call).to eq("pong")
    end

    it "integrates with the Registry" do
      tool = Strands.tool("registered_tool",
        description: "A tool to register"
      ) { "registered" }

      registry = Strands::Tools::Registry.new
      registry.register(tool)

      expect(registry.get("registered_tool").call).to eq("registered")
    end
  end
end
