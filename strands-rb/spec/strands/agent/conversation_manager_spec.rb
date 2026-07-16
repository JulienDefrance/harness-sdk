# frozen_string_literal: true

require "spec_helper"

RSpec.describe Strands::Agent::ConversationManager do
  describe "#apply" do
    it "raises NotImplementedError" do
      expect { described_class.new.apply([]) }.to raise_error(NotImplementedError)
    end
  end
end

RSpec.describe Strands::Agent::NullConversationManager do
  describe "#apply" do
    it "returns messages unchanged" do
      messages = [
        { role: :user, content: [{ text: "hello" }] },
        { role: :assistant, content: [{ text: "hi" }] }
      ]
      result = described_class.new.apply(messages)
      expect(result).to eq(messages)
    end

    it "handles empty messages" do
      expect(described_class.new.apply([])).to eq([])
    end
  end
end

RSpec.describe Strands::Agent::SlidingWindowConversationManager do
  subject(:manager) { described_class.new(window_size: 6) }

  let(:messages) do
    (1..10).map do |i|
      { role: i.odd? ? :user : :assistant, content: [{ text: "msg #{i}" }] }
    end
  end

  describe "#initialize" do
    it "uses default window_size of 40" do
      default = described_class.new
      expect(default.window_size).to eq(40)
    end

    it "accepts custom window_size" do
      expect(manager.window_size).to eq(6)
    end
  end

  describe "#apply" do
    it "returns messages unchanged when within window" do
      short = messages[0..3]
      expect(manager.apply(short)).to eq(short)
    end

    it "trims messages exceeding window_size" do
      result = manager.apply(messages)
      expect(result.length).to eq(6)
    end

    it "preserves the first pair when preserve_first_pair is true" do
      result = manager.apply(messages)
      expect(result[0][:content].first[:text]).to eq("msg 1")
      expect(result[1][:content].first[:text]).to eq("msg 2")
    end

    it "includes most recent messages after the first pair" do
      result = manager.apply(messages)
      # Should have first 2 + last 4
      expect(result.last[:content].first[:text]).to eq("msg 10")
      expect(result[-2][:content].first[:text]).to eq("msg 9")
    end

    it "does not preserve first pair when disabled" do
      no_preserve = described_class.new(window_size: 4, preserve_first_pair: false)
      result = no_preserve.apply(messages)
      expect(result.length).to eq(4)
      expect(result.first[:content].first[:text]).to eq("msg 7")
      expect(result.last[:content].first[:text]).to eq("msg 10")
    end

    it "handles exactly window_size messages" do
      exact = messages[0..5] # 6 messages
      expect(manager.apply(exact)).to eq(exact)
    end

    it "handles empty messages" do
      expect(manager.apply([])).to eq([])
    end

    it "handles single message" do
      single = [messages[0]]
      expect(manager.apply(single)).to eq(single)
    end
  end
end
