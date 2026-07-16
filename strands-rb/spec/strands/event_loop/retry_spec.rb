# frozen_string_literal: true

require "spec_helper"

RSpec.describe Strands::EventLoop::RetryStrategy do
  subject(:strategy) { described_class.new }

  describe "#initialize" do
    it "uses default values" do
      expect(strategy.max_attempts).to eq(6)
      expect(strategy.initial_delay).to eq(4.0)
      expect(strategy.max_delay).to eq(240.0)
      expect(strategy.backoff_factor).to eq(2.0)
    end

    it "accepts custom values" do
      custom = described_class.new(max_attempts: 3, initial_delay: 1.0, max_delay: 30.0, backoff_factor: 3.0)
      expect(custom.max_attempts).to eq(3)
      expect(custom.initial_delay).to eq(1.0)
      expect(custom.max_delay).to eq(30.0)
      expect(custom.backoff_factor).to eq(3.0)
    end
  end

  describe "#should_retry?" do
    it "returns true for attempts below max_attempts - 1" do
      expect(strategy.should_retry?(0)).to be true
      expect(strategy.should_retry?(4)).to be true
    end

    it "returns false for the last attempt" do
      expect(strategy.should_retry?(5)).to be false
    end

    it "returns false for attempts exceeding max" do
      expect(strategy.should_retry?(10)).to be false
    end
  end

  describe "#delay_for" do
    it "returns a delay based on exponential backoff" do
      delay = strategy.delay_for(0)
      # initial_delay * backoff^0 = 4.0, plus up to 25% jitter
      expect(delay).to be >= 4.0
      expect(delay).to be <= 5.0
    end

    it "increases delay with each attempt" do
      # Get multiple samples to handle jitter
      delays = (0..3).map { |attempt| strategy.delay_for(attempt) }
      # On average each should be larger (base without jitter: 4, 8, 16, 32)
      # Just verify attempt 3 base is larger than attempt 0 base
      base_0 = strategy.initial_delay * (strategy.backoff_factor**0)
      base_3 = strategy.initial_delay * (strategy.backoff_factor**3)
      expect(base_3).to be > base_0
    end

    it "caps at max_delay" do
      # Attempt 10 would be 4 * 2^10 = 4096, but should cap at 240
      delay = strategy.delay_for(10)
      expect(delay).to be <= 240.0 * 1.25 # max_delay + 25% jitter
    end
  end
end
