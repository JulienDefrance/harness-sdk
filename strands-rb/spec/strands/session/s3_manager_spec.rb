# frozen_string_literal: true

require "spec_helper"

RSpec.describe Strands::Session::S3Manager do
  # Stub the AWS classes to avoid requiring the real gem
  before do
    stub_const("Aws::S3::Client", Class.new)
    stub_const("Aws::S3::Errors::NoSuchKey", Class.new(StandardError))
    stub_const("Aws::S3::Errors::NotFound", Class.new(StandardError))
    allow(Aws::S3::Client).to receive(:new).and_return(instance_double("Aws::S3::Client"))
  end

  let(:mock_storage) { instance_double(Strands::Storage::S3) }

  before do
    allow(Strands::Storage::S3).to receive(:new).and_return(mock_storage)
  end

  subject(:manager) do
    described_class.new(bucket: "test-bucket", prefix: "sessions/", session_id: "test-session-123")
  end

  let(:agent) do
    double("Agent", messages: [])
  end

  describe "#initialize" do
    it "stores the session_id" do
      expect(manager.session_id).to eq("test-session-123")
    end

    it "generates a session_id when nil" do
      m = described_class.new(bucket: "b")
      expect(m.session_id).to match(/\A[0-9a-f-]{36}\z/)
    end

    it "creates a Storage::S3 instance" do
      expect(manager.storage).to eq(mock_storage)
    end
  end

  describe "#initialize_session" do
    it "calls restore to load existing state" do
      allow(mock_storage).to receive(:read)
        .with("test-session-123/state.json")
        .and_return(nil)

      manager.initialize_session(agent)
    end

    it "restores messages from storage" do
      messages = [{ "role" => "user", "content" => "hello" }]
      stored = JSON.generate({ session_id: "test-session-123", messages: messages, updated_at: Time.now.iso8601 })
      allow(mock_storage).to receive(:read)
        .with("test-session-123/state.json")
        .and_return(stored)

      agent_messages = []
      mock_agent = double("Agent", messages: agent_messages)
      allow(agent_messages).to receive(:respond_to?).with(:replace).and_return(true)
      allow(agent_messages).to receive(:replace)

      manager.initialize_session(mock_agent)
      expect(agent_messages).to have_received(:replace).with(messages)
    end
  end

  describe "#append_message" do
    it "is a no-op" do
      # Should not raise or call storage
      expect { manager.append_message({ role: "user", content: "hi" }, agent) }.not_to raise_error
    end
  end

  describe "#sync_agent" do
    it "writes agent messages as JSON to session key" do
      messages = [{ role: "user", content: "hello" }]
      mock_agent = double("Agent", messages: messages)

      expect(mock_storage).to receive(:write) do |key, data|
        expect(key).to eq("test-session-123/state.json")
        parsed = JSON.parse(data)
        expect(parsed["session_id"]).to eq("test-session-123")
        expect(parsed["messages"]).to eq([{ "role" => "user", "content" => "hello" }])
        expect(parsed["updated_at"]).not_to be_nil
      end

      manager.sync_agent(mock_agent)
    end
  end

  describe "#restore" do
    it "does nothing when no data exists" do
      allow(mock_storage).to receive(:read).and_return(nil)
      expect { manager.restore(agent) }.not_to raise_error
    end

    it "replaces agent messages from stored state" do
      messages = [{ "role" => "assistant", "content" => "hi" }]
      stored = JSON.generate({ session_id: "test-session-123", messages: messages, updated_at: Time.now.iso8601 })
      allow(mock_storage).to receive(:read).and_return(stored)

      agent_messages = []
      mock_agent = double("Agent", messages: agent_messages)
      allow(agent_messages).to receive(:respond_to?).with(:replace).and_return(true)
      allow(agent_messages).to receive(:replace)

      manager.restore(mock_agent)
      expect(agent_messages).to have_received(:replace).with(messages)
    end
  end
end
