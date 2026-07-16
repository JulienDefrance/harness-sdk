# frozen_string_literal: true

require "spec_helper"

RSpec.describe Strands::Storage::InMemory do
  subject(:storage) { described_class.new }

  describe "#write and #read" do
    it "stores and retrieves data" do
      storage.write("key1", "value1")
      expect(storage.read("key1")).to eq("value1")
    end

    it "returns nil for non-existent keys" do
      expect(storage.read("missing")).to be_nil
    end

    it "overwrites existing values" do
      storage.write("key1", "original")
      storage.write("key1", "updated")
      expect(storage.read("key1")).to eq("updated")
    end

    it "normalizes keys with multiple slashes" do
      storage.write("a//b///c", "data")
      expect(storage.read("a/b/c")).to eq("data")
    end

    it "strips leading and trailing slashes from keys" do
      storage.write("/a/b/", "data")
      expect(storage.read("a/b")).to eq("data")
    end
  end

  describe "#delete" do
    it "removes a stored value" do
      storage.write("key1", "value1")
      storage.delete("key1")
      expect(storage.read("key1")).to be_nil
    end

    it "is a no-op for non-existent keys" do
      expect { storage.delete("missing") }.not_to raise_error
    end
  end

  describe "#exists?" do
    it "returns true for existing keys" do
      storage.write("key1", "value1")
      expect(storage.exists?("key1")).to be true
    end

    it "returns false for non-existent keys" do
      expect(storage.exists?("missing")).to be false
    end

    it "returns false after deletion" do
      storage.write("key1", "value1")
      storage.delete("key1")
      expect(storage.exists?("key1")).to be false
    end
  end

  describe "#list" do
    before do
      storage.write("sessions/abc/state.json", "data1")
      storage.write("sessions/abc/messages.json", "data2")
      storage.write("sessions/def/state.json", "data3")
      storage.write("other/file.txt", "data4")
    end

    it "lists all keys with empty prefix" do
      keys = storage.list("")
      expect(keys).to contain_exactly(
        "other/file.txt",
        "sessions/abc/messages.json",
        "sessions/abc/state.json",
        "sessions/def/state.json"
      )
    end

    it "filters by prefix" do
      keys = storage.list("sessions/abc")
      expect(keys).to contain_exactly(
        "sessions/abc/messages.json",
        "sessions/abc/state.json"
      )
    end

    it "returns sorted keys" do
      keys = storage.list("")
      expect(keys).to eq(keys.sort)
    end

    it "returns empty array for non-matching prefix" do
      expect(storage.list("nonexistent")).to be_empty
    end
  end

  describe "#clear" do
    it "removes all entries" do
      storage.write("key1", "value1")
      storage.write("key2", "value2")
      storage.clear
      expect(storage.size).to eq(0)
    end
  end

  describe "key validation" do
    it "raises ArgumentError for empty keys" do
      expect { storage.write("", "data") }.to raise_error(ArgumentError, /must not be empty/)
    end

    it "raises ArgumentError for keys with '..' segments" do
      expect { storage.write("a/../b", "data") }.to raise_error(ArgumentError, /not allowed/)
    end
  end
end
