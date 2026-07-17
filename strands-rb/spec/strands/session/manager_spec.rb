# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe Strands::Session::Manager do
  describe "interface" do
    let(:manager_class) do
      Class.new(described_class) do
        attr_reader :initialized, :messages_appended, :synced

        def initialize
          @initialized = false
          @messages_appended = []
          @synced = 0
        end

        def initialize_session(agent)
          @initialized = true
        end

        def append_message(message, agent)
          @messages_appended << message
        end

        def sync_agent(agent)
          @synced += 1
        end

        def restore(agent)
          # no-op for test
        end
      end
    end

    let(:manager) { manager_class.new }

    it "includes Hooks::Provider" do
      expect(described_class.ancestors).to include(Strands::Hooks::Provider)
    end

    it "raises NotImplementedError for abstract methods" do
      abstract_manager = described_class.new
      agent = double("agent")

      expect { abstract_manager.initialize_session(agent) }.to raise_error(NotImplementedError)
      expect { abstract_manager.append_message({}, agent) }.to raise_error(NotImplementedError)
      expect { abstract_manager.sync_agent(agent) }.to raise_error(NotImplementedError)
      expect { abstract_manager.restore(agent) }.to raise_error(NotImplementedError)
    end

    describe "#register_hooks" do
      let(:registry) { Strands::Hooks::Registry.new }
      let(:agent) { double("agent", messages: []) }

      before do
        manager.register_hooks(registry)
      end

      it "registers AgentInitializedEvent callback" do
        event = Strands::Hooks::AgentInitializedEvent.new(agent: agent)
        registry.fire(event)
        expect(manager.initialized).to be true
      end

      it "registers MessageAddedEvent callback for append_message" do
        message = { role: "user", content: [{ text: "Hello" }] }
        event = Strands::Hooks::MessageAddedEvent.new(agent: agent, message: message)
        registry.fire(event)
        expect(manager.messages_appended).to include(message)
      end

      it "registers MessageAddedEvent callback for sync_agent" do
        message = { role: "user", content: [{ text: "Hello" }] }
        event = Strands::Hooks::MessageAddedEvent.new(agent: agent, message: message)
        registry.fire(event)
        # sync_agent is called once from MessageAddedEvent
        expect(manager.synced).to be >= 1
      end

      it "registers AfterInvocationEvent callback for sync_agent" do
        event = Strands::Hooks::AfterInvocationEvent.new(agent: agent)
        registry.fire(event)
        expect(manager.synced).to be >= 1
      end
    end
  end
end

RSpec.describe Strands::Session::FileManager do
  let(:tmpdir) { Dir.mktmpdir("strands_session_test_") }
  subject(:manager) { described_class.new(base_dir: tmpdir, session_id: "test-session") }

  after do
    FileUtils.rm_rf(tmpdir)
  end

  describe "#initialize_session" do
    let(:agent) { double("agent", messages: []) }

    it "does not fail when no session exists" do
      expect { manager.initialize_session(agent) }.not_to raise_error
    end
  end

  describe "#sync_agent and #restore" do
    let(:messages) { [{ role: "user", content: [{ text: "Hello" }] }] }
    let(:agent) { double("agent", messages: messages) }
    let(:restore_agent) do
      obj = double("agent")
      msgs = []
      allow(obj).to receive(:messages).and_return(msgs)
      allow(msgs).to receive(:replace) { |new_msgs| msgs.replace(new_msgs) }
      obj
    end

    it "persists and restores agent messages" do
      manager.sync_agent(agent)
      manager.restore(restore_agent)
      expect(restore_agent.messages).to eq(messages)
    end
  end

  describe "#session_id" do
    it "uses provided session_id" do
      expect(manager.session_id).to eq("test-session")
    end

    it "generates a UUID if not provided" do
      auto_manager = described_class.new(base_dir: tmpdir)
      expect(auto_manager.session_id).to match(/\A[0-9a-f-]{36}\z/)
    end
  end
end
