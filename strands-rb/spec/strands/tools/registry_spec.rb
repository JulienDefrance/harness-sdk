# frozen_string_literal: true

require "spec_helper"

RSpec.describe Strands::Tools::Registry do
  subject(:registry) { described_class.new }

  let(:calculator) do
    Strands::Tools::Definition.new(
      name: "calculator",
      description: "Evaluates math",
      input_schema: {
        properties: { expression: { type: "string", description: "Math expression" } },
        required: ["expression"]
      },
      callable: ->(expression:) { eval(expression).to_s }
    )
  end

  let(:greeter) do
    Strands::Tools::Definition.new(
      name: "greeter",
      description: "Says hello",
      input_schema: {
        properties: { name: { type: "string", description: "Name to greet" } },
        required: ["name"]
      },
      callable: ->(name:) { "Hello, #{name}!" }
    )
  end

  describe "#register" do
    it "registers a Definition" do
      registry.register(calculator)
      expect(registry.size).to eq(1)
    end

    it "returns the registered definition" do
      result = registry.register(calculator)
      expect(result).to eq(calculator)
    end

    it "raises ArgumentError for duplicate names" do
      registry.register(calculator)
      expect {
        registry.register(calculator)
      }.to raise_error(ArgumentError, /already registered/)
    end

    it "raises ArgumentError for name conflicts with dashes vs underscores" do
      dash_tool = Strands::Tools::Definition.new(
        name: "my-tool",
        description: "Dashed",
        input_schema: {},
        callable: -> { nil }
      )
      underscore_tool = Strands::Tools::Definition.new(
        name: "my_tool",
        description: "Underscored",
        input_schema: {},
        callable: -> { nil }
      )

      registry.register(dash_tool)
      expect {
        registry.register(underscore_tool)
      }.to raise_error(ArgumentError, /conflicts with/)
    end

    it "registers a Hash with required keys" do
      registry.register(
        name: "hash_tool",
        description: "From hash",
        input_schema: {},
        callable: -> { "hash result" }
      )

      expect(registry.get("hash_tool")).to be_a(Strands::Tools::Definition)
    end

    it "registers an object responding to #name and #call" do
      tool_object = Object.new
      def tool_object.name = "obj_tool"
      def tool_object.description = "Object tool"
      def tool_object.input_schema = {}
      def tool_object.call(**_) = "obj result"

      registry.register(tool_object)
      expect(registry.get("obj_tool")).to be_a(Strands::Tools::Definition)
    end

    it "raises ArgumentError for unrecognized formats" do
      expect {
        registry.register(42)
      }.to raise_error(ArgumentError, /Unrecognized tool format/)
    end
  end

  describe "#get" do
    it "returns the tool definition by name" do
      registry.register(calculator)
      expect(registry.get("calculator")).to eq(calculator)
    end

    it "returns nil for unknown tools" do
      expect(registry.get("nonexistent")).to be_nil
    end
  end

  describe "#fetch" do
    it "returns the tool definition by name" do
      registry.register(calculator)
      expect(registry.fetch("calculator")).to eq(calculator)
    end

    it "raises KeyError for unknown tools" do
      expect {
        registry.fetch("nonexistent")
      }.to raise_error(KeyError, /not found/)
    end
  end

  describe "#list" do
    it "returns all registered tool names" do
      registry.register(calculator)
      registry.register(greeter)

      expect(registry.list).to contain_exactly("calculator", "greeter")
    end

    it "returns empty array when no tools registered" do
      expect(registry.list).to eq([])
    end
  end

  describe "#size" do
    it "returns the number of registered tools" do
      expect(registry.size).to eq(0)
      registry.register(calculator)
      expect(registry.size).to eq(1)
    end
  end

  describe "#registered?" do
    it "returns true for registered tools" do
      registry.register(calculator)
      expect(registry.registered?("calculator")).to be true
    end

    it "returns false for unregistered tools" do
      expect(registry.registered?("unknown")).to be false
    end
  end

  describe "#tool_specs" do
    it "returns ToolSpec objects for all tools" do
      registry.register(calculator)
      registry.register(greeter)

      specs = registry.tool_specs
      expect(specs.length).to eq(2)
      expect(specs).to all(be_a(Strands::Types::Tools::ToolSpec))
      expect(specs.map(&:name)).to contain_exactly("calculator", "greeter")
    end

    it "returns empty array when no tools registered" do
      expect(registry.tool_specs).to eq([])
    end
  end

  describe "#unregister" do
    it "removes a tool from the registry" do
      registry.register(calculator)
      registry.unregister("calculator")
      expect(registry.registered?("calculator")).to be false
    end

    it "returns the removed definition" do
      registry.register(calculator)
      result = registry.unregister("calculator")
      expect(result).to eq(calculator)
    end

    it "returns nil for unknown tools" do
      expect(registry.unregister("unknown")).to be_nil
    end
  end

  describe "#process_tools" do
    it "registers multiple tools and returns their names" do
      names = registry.process_tools([calculator, greeter])
      expect(names).to contain_exactly("calculator", "greeter")
      expect(registry.size).to eq(2)
    end

    it "handles nested arrays" do
      names = registry.process_tools([[calculator], [greeter]])
      expect(names).to contain_exactly("calculator", "greeter")
    end

    it "handles hashes in the array" do
      names = registry.process_tools([
        { name: "inline", description: "Inline tool", input_schema: {}, callable: -> { "ok" } }
      ])
      expect(names).to eq(["inline"])
    end
  end

  describe "#clear" do
    it "removes all tools" do
      registry.register(calculator)
      registry.register(greeter)
      registry.clear
      expect(registry.size).to eq(0)
    end
  end
end
