# frozen_string_literal: true

require "spec_helper"
require "stringio"

RSpec.describe Strands::Handlers::CallbackHandler do
  describe "#call" do
    it "raises NotImplementedError for the base class" do
      expect { described_class.new.call(data: "test") }.to raise_error(NotImplementedError)
    end
  end
end

RSpec.describe Strands::Handlers::Printing do
  let(:output) { StringIO.new }
  subject(:handler) { described_class.new(output: output) }

  describe "#call" do
    it "prints text data without newline when not complete" do
      handler.call(data: "Hello", complete: false)
      expect(output.string).to eq("Hello")
    end

    it "prints text data with newline when complete" do
      handler.call(data: "Done", complete: true)
      expect(output.string).to eq("Done\n")
    end

    it "prints empty line when complete with no data" do
      handler.call(data: "", complete: true)
      expect(output.string).to eq("\n")
    end

    it "does nothing when data is empty and not complete" do
      handler.call(data: "", complete: false)
      expect(output.string).to eq("")
    end

    it "does nothing when data is nil" do
      handler.call(data: nil, complete: false)
      expect(output.string).to eq("")
    end

    it "prints tool use info when verbose" do
      tool_use = Struct.new(:name).new("calculator")
      handler.call(tool_use: tool_use)
      expect(output.string).to include("Tool #1: calculator")
    end

    it "increments tool count" do
      tool_use = Struct.new(:name).new("tool_a")
      handler.call(tool_use: tool_use)
      handler.call(tool_use: tool_use)
      expect(handler.tool_count).to eq(2)
      expect(output.string).to include("Tool #1")
      expect(output.string).to include("Tool #2")
    end

    it "does not print tool info when verbose_tool_use is false" do
      quiet = described_class.new(output: output, verbose_tool_use: false)
      tool_use = Struct.new(:name).new("calculator")
      quiet.call(tool_use: tool_use)
      expect(output.string).to eq("")
    end

    it "streams multiple deltas correctly" do
      handler.call(data: "Hello", complete: false)
      handler.call(data: " World", complete: false)
      handler.call(data: "!", complete: true)
      expect(output.string).to eq("Hello World!\n")
    end
  end
end

RSpec.describe Strands::Handlers::Null do
  describe "#call" do
    it "does nothing with any input" do
      handler = described_class.new
      # Should not raise
      expect { handler.call(data: "test", complete: true) }.not_to raise_error
    end

    it "returns nil" do
      handler = described_class.new
      expect(handler.call(data: "test")).to be_nil
    end
  end
end
