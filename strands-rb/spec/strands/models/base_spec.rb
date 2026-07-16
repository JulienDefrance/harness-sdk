# frozen_string_literal: true

require "spec_helper"

RSpec.describe Strands::Models::Base do
  let(:test_class) do
    Class.new do
      include Strands::Models::Base
    end
  end

  subject(:model) { test_class.new }

  describe "#stream" do
    it "raises NotImplementedError" do
      expect { model.stream([]) }.to raise_error(NotImplementedError, /must be implemented/)
    end

    it "includes the class name in the error message" do
      expect { model.stream([]) }.to raise_error(NotImplementedError, /stream/)
    end
  end

  describe "#update_config" do
    it "raises NotImplementedError" do
      expect { model.update_config(model_id: "test") }.to raise_error(NotImplementedError, /must be implemented/)
    end
  end

  describe "#get_config" do
    it "raises NotImplementedError" do
      expect { model.get_config }.to raise_error(NotImplementedError, /must be implemented/)
    end
  end

  describe "#stateful?" do
    it "returns false by default" do
      expect(model.stateful?).to be false
    end
  end

  context "when included in a concrete class" do
    let(:concrete_class) do
      Class.new do
        include Strands::Models::Base

        def initialize
          @config = { model_id: "test-model" }
        end

        def stream(messages, system_prompt: nil, tools: nil, tool_choice: nil, **kwargs)
          yield Strands::Types::Streaming::StreamEvent.new(
            message_start: Strands::Types::Streaming::MessageStartEvent.new(role: :assistant)
          )
        end

        def update_config(**opts)
          @config.merge!(opts)
        end

        def get_config
          @config.dup
        end
      end
    end

    let(:concrete_model) { concrete_class.new }

    it "allows stream to yield events" do
      events = []
      concrete_model.stream([{ role: :user, content: "Hi" }]) { |e| events << e }
      expect(events.length).to eq(1)
      expect(events.first.message_start.role).to eq(:assistant)
    end

    it "allows update_config to modify configuration" do
      concrete_model.update_config(model_id: "new-model")
      expect(concrete_model.get_config[:model_id]).to eq("new-model")
    end

    it "allows get_config to return configuration" do
      expect(concrete_model.get_config[:model_id]).to eq("test-model")
    end
  end
end
