# frozen_string_literal: true

RSpec.describe Strands::Types::Tools do
  describe Strands::Types::Tools::ToolSpec do
    it "creates a tool spec with required fields" do
      spec = described_class.new(
        name: "calculator",
        description: "Performs arithmetic",
        input_schema: {
          "type" => "object",
          "properties" => {
            "expression" => { "type" => "string" }
          },
          "required" => ["expression"]
        }
      )
      expect(spec.name).to eq("calculator")
      expect(spec.description).to eq("Performs arithmetic")
      expect(spec.input_schema).to be_a(Hash)
      expect(spec.input_schema["type"]).to eq("object")
    end

    it "has nil output_schema by default" do
      spec = described_class.new(
        name: "search",
        description: "Search the web",
        input_schema: { "type" => "object" }
      )
      expect(spec.output_schema).to be_nil
    end

    it "accepts an optional output_schema" do
      spec = described_class.new(
        name: "search",
        description: "Search",
        input_schema: { "type" => "object" },
        output_schema: { "type" => "array" }
      )
      expect(spec.output_schema).to eq({ "type" => "array" })
    end
  end

  describe Strands::Types::Tools::Tool do
    it "wraps a tool spec" do
      spec = Strands::Types::Tools::ToolSpec.new(
        name: "calc",
        description: "Calculator",
        input_schema: {}
      )
      tool = described_class.new(tool_spec: spec)
      expect(tool.tool_spec).to eq(spec)
      expect(tool.tool_spec.name).to eq("calc")
    end
  end

  describe Strands::Types::Tools::ToolUse do
    it "creates a tool use request" do
      tu = described_class.new(
        name: "calculator",
        tool_use_id: "tu-abc-123",
        input: { "expression" => "2 + 2" }
      )
      expect(tu.name).to eq("calculator")
      expect(tu.tool_use_id).to eq("tu-abc-123")
      expect(tu.input).to eq({ "expression" => "2 + 2" })
    end

    it "has nil reasoning_signature by default" do
      tu = described_class.new(name: "x", tool_use_id: "id", input: {})
      expect(tu.reasoning_signature).to be_nil
    end

    it "accepts a reasoning_signature" do
      tu = described_class.new(
        name: "x",
        tool_use_id: "id",
        input: {},
        reasoning_signature: "sig-xyz"
      )
      expect(tu.reasoning_signature).to eq("sig-xyz")
    end
  end

  describe Strands::Types::Tools::ToolResultContent do
    it "creates text result content" do
      content = described_class.new(text: "The answer is 4")
      expect(content.text).to eq("The answer is 4")
    end

    it "creates json result content" do
      content = described_class.new(json: { "result" => 4 })
      expect(content.json).to eq({ "result" => 4 })
    end

    it "creates image result content" do
      image = Strands::Types::Media::ImageContent.new(
        format: "png",
        source: Strands::Types::Media::ImageSource.new(bytes: "img_data")
      )
      content = described_class.new(image: image)
      expect(content.image.format).to eq("png")
    end

    it "creates document result content" do
      doc = Strands::Types::Media::DocumentContent.new(
        format: "pdf",
        name: "out.pdf",
        source: Strands::Types::Media::DocumentSource.new(bytes: "pdf_data")
      )
      content = described_class.new(document: doc)
      expect(content.document.name).to eq("out.pdf")
    end
  end

  describe Strands::Types::Tools::ToolResult do
    it "creates a successful tool result" do
      content = [Strands::Types::Tools::ToolResultContent.new(text: "done")]
      result = described_class.new(
        tool_use_id: "tu-123",
        content: content,
        status: :success
      )
      expect(result.tool_use_id).to eq("tu-123")
      expect(result.content).to eq(content)
      expect(result.status).to eq(:success)
    end

    it "creates an error tool result" do
      content = [Strands::Types::Tools::ToolResultContent.new(text: "failed")]
      result = described_class.new(
        tool_use_id: "tu-456",
        content: content,
        status: :error
      )
      expect(result.status).to eq(:error)
    end

    it "raises ArgumentError for invalid status" do
      expect {
        described_class.new(
          tool_use_id: "tu-789",
          content: [],
          status: :unknown
        )
      }.to raise_error(ArgumentError, /status must be one of/)
    end
  end

  describe Strands::Types::Tools::ToolContext do
    it "creates a tool context with required fields" do
      tool_use = Strands::Types::Tools::ToolUse.new(
        name: "calc",
        tool_use_id: "tu-1",
        input: {}
      )
      agent = Object.new
      ctx = described_class.new(tool_use: tool_use, agent: agent)
      expect(ctx.tool_use).to eq(tool_use)
      expect(ctx.agent).to eq(agent)
      expect(ctx.invocation_state).to eq({})
    end

    it "accepts custom invocation_state" do
      tool_use = Strands::Types::Tools::ToolUse.new(name: "x", tool_use_id: "id", input: {})
      ctx = described_class.new(
        tool_use: tool_use,
        agent: nil,
        invocation_state: { session_id: "abc" }
      )
      expect(ctx.invocation_state).to eq({ session_id: "abc" })
    end
  end

  describe Strands::Types::Tools::ToolConfig do
    it "creates a tool configuration" do
      spec = Strands::Types::Tools::ToolSpec.new(
        name: "calc",
        description: "Calculator",
        input_schema: {}
      )
      tool = Strands::Types::Tools::Tool.new(tool_spec: spec)
      config = described_class.new(
        tools: [tool],
        tool_choice: Strands::Types::Tools::ToolChoiceAuto.new
      )
      expect(config.tools.size).to eq(1)
      expect(config.tool_choice).to be_a(Strands::Types::Tools::ToolChoiceAuto)
    end

    it "supports ToolChoiceTool for forcing a specific tool" do
      choice = Strands::Types::Tools::ToolChoiceTool.new(name: "search")
      expect(choice.name).to eq("search")
    end

    it "supports ToolChoiceAny" do
      choice = Strands::Types::Tools::ToolChoiceAny.new
      expect(choice).to be_a(Strands::Types::Tools::ToolChoiceAny)
    end
  end
end
