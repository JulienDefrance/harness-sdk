# frozen_string_literal: true

RSpec.describe Strands::Types::Content do
  describe Strands::Types::Content::ContentBlock do
    it "creates a text content block" do
      block = described_class.new(text: "Hello, world!")
      expect(block.text).to eq("Hello, world!")
      expect(block.content_type).to eq(:text)
    end

    it "creates a tool_use content block" do
      tool_use = Strands::Types::Tools::ToolUse.new(
        name: "calculator",
        tool_use_id: "tu-123",
        input: { expression: "2+2" }
      )
      block = described_class.new(tool_use: tool_use)
      expect(block.tool_use).to eq(tool_use)
      expect(block.content_type).to eq(:tool_use)
    end

    it "creates a tool_result content block" do
      result_content = Strands::Types::Tools::ToolResultContent.new(text: "4")
      tool_result = Strands::Types::Tools::ToolResult.new(
        tool_use_id: "tu-123",
        content: [result_content],
        status: :success
      )
      block = described_class.new(tool_result: tool_result)
      expect(block.tool_result).to eq(tool_result)
      expect(block.content_type).to eq(:tool_result)
    end

    it "creates an image content block" do
      image = Strands::Types::Media::ImageContent.new(
        format: "png",
        source: Strands::Types::Media::ImageSource.new(bytes: "image_data")
      )
      block = described_class.new(image: image)
      expect(block.image).to eq(image)
      expect(block.content_type).to eq(:image)
    end

    it "creates a document content block" do
      doc = Strands::Types::Media::DocumentContent.new(
        format: "pdf",
        name: "report.pdf",
        source: Strands::Types::Media::DocumentSource.new(bytes: "pdf_data")
      )
      block = described_class.new(document: doc)
      expect(block.document).to eq(doc)
      expect(block.content_type).to eq(:document)
    end

    it "creates a video content block" do
      video = Strands::Types::Media::VideoContent.new(
        format: "mp4",
        source: Strands::Types::Media::VideoSource.new(bytes: "video_data")
      )
      block = described_class.new(video: video)
      expect(block.video).to eq(video)
      expect(block.content_type).to eq(:video)
    end

    it "creates a reasoning_content block" do
      reasoning = Strands::Types::Content::ReasoningContentBlock.new(
        reasoning_text: Strands::Types::Content::ReasoningTextBlock.new(text: "I think because...")
      )
      block = described_class.new(reasoning_content: reasoning)
      expect(block.reasoning_content).to eq(reasoning)
      expect(block.content_type).to eq(:reasoning_content)
    end

    it "creates a guard_content block" do
      guard = Strands::Types::Content::GuardContent.new(
        text: Strands::Types::Content::GuardContentText.new(text: "evaluate this")
      )
      block = described_class.new(guard_content: guard)
      expect(block.guard_content).to eq(guard)
      expect(block.content_type).to eq(:guard_content)
    end

    it "creates a cache_point block" do
      cache = Strands::Types::Content::CachePoint.new(type: "default", ttl: "5m")
      block = described_class.new(cache_point: cache)
      expect(block.cache_point).to eq(cache)
      expect(block.content_type).to eq(:cache_point)
    end

    it "returns nil content_type when empty" do
      block = described_class.new
      expect(block.content_type).to be_nil
    end
  end

  describe Strands::Types::Content::Message do
    it "creates a user message with content" do
      content = [Strands::Types::Content::ContentBlock.new(text: "Hi")]
      msg = described_class.new(role: :user, content: content)
      expect(msg.role).to eq(:user)
      expect(msg.content).to eq(content)
    end

    it "creates an assistant message" do
      msg = described_class.new(role: :assistant, content: [])
      expect(msg.role).to eq(:assistant)
    end

    it "raises ArgumentError for invalid role" do
      expect {
        described_class.new(role: :system, content: [])
      }.to raise_error(ArgumentError, /role must be one of/)
    end

    it "has nil tracking_id by default" do
      msg = described_class.new(role: :user, content: [])
      expect(msg.tracking_id).to be_nil
    end

    it "accepts an explicit tracking_id" do
      msg = described_class.new(role: :user, content: [], tracking_id: "custom-id")
      expect(msg.tracking_id).to eq("custom-id")
    end

    it "generates a tracking_id with ensure_tracking_id!" do
      msg = described_class.new(role: :user, content: [])
      id = msg.ensure_tracking_id!
      expect(id).to match(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/)
      expect(msg.tracking_id).to eq(id)
    end

    it "does not overwrite existing tracking_id" do
      msg = described_class.new(role: :user, content: [], tracking_id: "keep-this")
      msg.ensure_tracking_id!
      expect(msg.tracking_id).to eq("keep-this")
    end

    it "accepts optional metadata" do
      metadata = Strands::Types::Content::MessageMetadata.new(custom: { source: "test" })
      msg = described_class.new(role: :user, content: [], metadata: metadata)
      expect(msg.metadata.custom).to eq({ source: "test" })
    end
  end

  describe Strands::Types::Content::SystemContentBlock do
    it "creates a system content block with text" do
      block = described_class.new(text: "You are a helpful assistant")
      expect(block.text).to eq("You are a helpful assistant")
      expect(block.cache_point).to be_nil
    end

    it "creates a system content block with cache point" do
      cache = Strands::Types::Content::CachePoint.new
      block = described_class.new(text: "System prompt", cache_point: cache)
      expect(block.cache_point.type).to eq("default")
    end
  end

  describe Strands::Types::Content::CachePoint do
    it "defaults type to 'default'" do
      cp = described_class.new
      expect(cp.type).to eq("default")
    end

    it "accepts a custom type and ttl" do
      cp = described_class.new(type: "custom", ttl: "1h")
      expect(cp.type).to eq("custom")
      expect(cp.ttl).to eq("1h")
    end
  end

  describe ".split_system_prompt" do
    it "splits a string system prompt" do
      str, blocks = described_class.split_system_prompt("Be helpful")
      expect(str).to eq("Be helpful")
      expect(blocks.size).to eq(1)
      expect(blocks.first.text).to eq("Be helpful")
    end

    it "splits an array system prompt" do
      blocks_input = [
        Strands::Types::Content::SystemContentBlock.new(text: "Part 1"),
        Strands::Types::Content::SystemContentBlock.new(text: "Part 2")
      ]
      str, blocks = described_class.split_system_prompt(blocks_input)
      expect(str).to eq("Part 1\nPart 2")
      expect(blocks).to eq(blocks_input)
    end

    it "returns nils for nil input" do
      str, blocks = described_class.split_system_prompt(nil)
      expect(str).to be_nil
      expect(blocks).to be_nil
    end

    it "handles array with no text elements" do
      blocks_input = [Strands::Types::Content::SystemContentBlock.new(cache_point: Strands::Types::Content::CachePoint.new)]
      str, blocks = described_class.split_system_prompt(blocks_input)
      expect(str).to be_nil
      expect(blocks).to eq(blocks_input)
    end
  end
end
