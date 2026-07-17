# frozen_string_literal: true

require "spec_helper"

RSpec.describe Strands::Tools::Executor do
  let(:registry) { Strands::Tools::Registry.new }
  subject(:executor) { described_class.new(registry) }

  let(:calculator) do
    Strands::Tools::Definition.new(
      name: "calculator",
      description: "Evaluates math",
      input_schema: {
        properties: { expression: { type: "string" } },
        required: ["expression"]
      },
      callable: ->(expression:) { eval(expression).to_s }
    )
  end

  let(:failing_tool) do
    Strands::Tools::Definition.new(
      name: "failing",
      description: "Always fails",
      input_schema: {},
      callable: -> { raise RuntimeError, "Something went wrong" }
    )
  end

  let(:hash_returning_tool) do
    Strands::Tools::Definition.new(
      name: "hash_tool",
      description: "Returns a hash",
      input_schema: {},
      callable: -> { { result: "data", count: 42 } }
    )
  end

  before do
    registry.register(calculator)
    registry.register(failing_tool)
    registry.register(hash_returning_tool)
  end

  describe "#execute" do
    context "with a valid tool use" do
      let(:tool_use) do
        Strands::Types::Tools::ToolUse.new(
          name: "calculator",
          tool_use_id: "use-001",
          input: { "expression" => "2 + 3" }
        )
      end

      it "returns a success ToolResult" do
        result = executor.execute(tool_use)
        expect(result).to be_a(Strands::Types::Tools::ToolResult)
        expect(result.status).to eq(:success)
        expect(result.tool_use_id).to eq("use-001")
      end

      it "contains the tool output in content" do
        result = executor.execute(tool_use)
        expect(result.content.first.text).to eq("5")
      end
    end

    context "when tool is not found" do
      let(:tool_use) do
        Strands::Types::Tools::ToolUse.new(
          name: "nonexistent",
          tool_use_id: "use-002",
          input: {}
        )
      end

      it "returns an error ToolResult" do
        result = executor.execute(tool_use)
        expect(result.status).to eq(:error)
        expect(result.tool_use_id).to eq("use-002")
      end

      it "includes error message about tool not found" do
        result = executor.execute(tool_use)
        expect(result.content.first.text).to include("not found")
      end
    end

    context "when tool raises an exception" do
      let(:tool_use) do
        Strands::Types::Tools::ToolUse.new(
          name: "failing",
          tool_use_id: "use-003",
          input: {}
        )
      end

      it "returns an error ToolResult instead of crashing" do
        result = executor.execute(tool_use)
        expect(result.status).to eq(:error)
      end

      it "includes the error class and message" do
        result = executor.execute(tool_use)
        expect(result.content.first.text).to include("RuntimeError")
        expect(result.content.first.text).to include("Something went wrong")
      end
    end

    context "when tool returns a hash" do
      let(:tool_use) do
        Strands::Types::Tools::ToolUse.new(
          name: "hash_tool",
          tool_use_id: "use-004",
          input: {}
        )
      end

      it "wraps the hash in ToolResultContent with json field" do
        result = executor.execute(tool_use)
        expect(result.status).to eq(:success)
        expect(result.content.first.json).to eq({ result: "data", count: 42 })
      end
    end

    context "when tool returns nil" do
      let(:nil_tool) do
        Strands::Tools::Definition.new(
          name: "nil_tool",
          description: "Returns nil",
          input_schema: {},
          callable: -> { nil }
        )
      end

      let(:tool_use) do
        Strands::Types::Tools::ToolUse.new(
          name: "nil_tool",
          tool_use_id: "use-005",
          input: {}
        )
      end

      before { registry.register(nil_tool) }

      it "returns a success result with empty text" do
        result = executor.execute(tool_use)
        expect(result.status).to eq(:success)
        expect(result.content.first.text).to eq("")
      end
    end

    context "with agent and invocation_state" do
      let(:context_tool) do
        Strands::Tools::Definition.new(
          name: "context_tool",
          description: "Uses context",
          input_schema: {},
          callable: ->(tool_context:) { "agent: #{tool_context.agent}" }
        )
      end

      let(:tool_use) do
        Strands::Types::Tools::ToolUse.new(
          name: "context_tool",
          tool_use_id: "use-006",
          input: {}
        )
      end

      before { registry.register(context_tool) }

      it "passes agent and invocation_state via ToolContext" do
        result = executor.execute(tool_use, agent: "my_agent", invocation_state: { key: "val" })
        expect(result.status).to eq(:success)
        expect(result.content.first.text).to include("my_agent")
      end
    end

    context "with nil input" do
      let(:no_input_tool) do
        Strands::Tools::Definition.new(
          name: "no_input",
          description: "No input needed",
          input_schema: {},
          callable: -> { "done" }
        )
      end

      let(:tool_use) do
        Strands::Types::Tools::ToolUse.new(
          name: "no_input",
          tool_use_id: "use-007",
          input: nil
        )
      end

      before { registry.register(no_input_tool) }

      it "handles nil input gracefully" do
        result = executor.execute(tool_use)
        expect(result.status).to eq(:success)
        expect(result.content.first.text).to eq("done")
      end
    end
  end
end
