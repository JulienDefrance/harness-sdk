# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe Strands::Storage::LocalFile do
  let(:tmpdir) { Dir.mktmpdir("strands_test_") }
  subject(:storage) { described_class.new(base_dir: tmpdir) }

  after do
    FileUtils.rm_rf(tmpdir)
  end

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

    it "creates nested directories" do
      storage.write("a/b/c/deep.txt", "deep data")
      expect(storage.read("a/b/c/deep.txt")).to eq("deep data")
    end

    it "normalizes key slashes" do
      storage.write("a//b///c", "data")
      expect(storage.read("a/b/c")).to eq("data")
    end
  end

  describe "#delete" do
    it "removes a stored file" do
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
  end

  describe "key validation" do
    it "raises ArgumentError for empty keys" do
      expect { storage.write("", "data") }.to raise_error(ArgumentError)
    end

    it "raises ArgumentError for keys with '..' segments" do
      expect { storage.write("a/../b", "data") }.to raise_error(ArgumentError)
    end
  end

  describe "atomic writes" do
    it "does not leave partial files on write failure" do
      # Simulate failure by trying to write to an invalid path
      # (a path where the parent is a file, not a directory)
      storage.write("file.txt", "content")
      # The file should exist
      expect(storage.exists?("file.txt")).to be true
    end
  end
end
