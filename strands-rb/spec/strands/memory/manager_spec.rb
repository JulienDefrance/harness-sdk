# frozen_string_literal: true

require "spec_helper"

RSpec.describe Strands::Memory::Manager do
  let(:store) { Strands::Memory::InMemoryStore.new(name: "facts") }
  subject(:manager) { described_class.new(stores: [store]) }

  describe "#add" do
    it "adds content as a memory entry" do
      entry = manager.add("The sky is blue")
      expect(entry).to be_a(Strands::Memory::MemoryEntry)
      expect(entry.content).to eq("The sky is blue")
      expect(entry.id).not_to be_nil
    end

    it "stores entry in the specified store" do
      manager.add("The sky is blue")
      expect(store.size).to eq(1)
    end

    it "accepts metadata" do
      entry = manager.add("Important fact", metadata: { source: "observation" })
      expect(entry.metadata).to eq({ source: "observation" })
    end
  end

  describe "#search" do
    before do
      manager.add("The sky is blue")
      manager.add("Grass is green")
      manager.add("The ocean is blue")
    end

    it "returns matching entries" do
      results = manager.search("blue")
      expect(results.size).to eq(2)
      expect(results.map(&:content)).to include("The sky is blue", "The ocean is blue")
    end

    it "returns empty array when no matches" do
      results = manager.search("red")
      expect(results).to be_empty
    end

    it "respects max_results" do
      results = manager.search("blue", max_results: 1)
      expect(results.size).to eq(1)
    end

    it "sets store_name on results" do
      results = manager.search("sky")
      expect(results.first.store_name).to eq("facts")
    end
  end

  describe "#search_memory (tool handler)" do
    before do
      manager.add("Ruby is a programming language")
    end

    it "returns structured results" do
      result = manager.search_memory({ query: "Ruby" })
      expect(result[:count]).to eq(1)
      expect(result[:results].first[:content]).to eq("Ruby is a programming language")
    end
  end

  describe "#add_memory (tool handler)" do
    it "stores content and returns confirmation" do
      result = manager.add_memory({ content: "New fact", metadata: { tag: "test" } })
      expect(result[:stored]).to be true
      expect(result[:id]).not_to be_nil
      expect(result[:content]).to eq("New fact")
    end
  end

  describe "multiple stores" do
    let(:store2) { Strands::Memory::InMemoryStore.new(name: "notes") }
    let(:multi_manager) { described_class.new(stores: [store, store2]) }

    it "searches across all stores" do
      multi_manager.add("Fact one")
      # Add to second store only
      entry = Strands::Memory::MemoryEntry.new(content: "Note about one")
      store2.add(entry)

      results = multi_manager.search("one")
      expect(results.size).to eq(2)
    end

    it "filters by store name" do
      multi_manager.add("Shared content")
      results = multi_manager.search("Shared", stores: ["facts"])
      expect(results.size).to eq(1)
      expect(results.first.store_name).to eq("facts")
    end
  end

  describe "plugin interface" do
    it "includes Plugins::Base" do
      expect(described_class.ancestors).to include(Strands::Plugins::Base)
    end

    it "has a plugin name" do
      expect(manager.name).to eq("memory-manager")
    end

    it "declares plugin tools" do
      tools = described_class.tool_methods
      tool_names = tools.map { |t| t[:method_name] }
      expect(tool_names).to include(:search_memory, :add_memory)
    end
  end
end
