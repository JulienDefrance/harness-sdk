# frozen_string_literal: true

RSpec.describe Strands::Types::Exceptions do
  describe Strands::Types::Exceptions::EventLoopError do
    it "wraps an original exception" do
      original = RuntimeError.new("something went wrong")
      error = described_class.new(original)
      expect(error.message).to eq("something went wrong")
      expect(error.original_exception).to eq(original)
      expect(error.request_state).to eq({})
    end

    it "stores request state" do
      original = StandardError.new("fail")
      state = { messages: [], model: "claude" }
      error = described_class.new(original, request_state: state)
      expect(error.request_state).to eq(state)
    end

    it "inherits from Strands::Error" do
      error = described_class.new(RuntimeError.new("x"))
      expect(error).to be_a(Strands::Error)
      expect(error).to be_a(StandardError)
    end
  end

  describe Strands::Types::Exceptions::ContextWindowOverflowError do
    it "can be raised with a message" do
      expect {
        raise described_class, "Context window exceeded: 200k tokens"
      }.to raise_error(described_class, "Context window exceeded: 200k tokens")
    end

    it "inherits from Strands::Error" do
      error = described_class.new("overflow")
      expect(error).to be_a(Strands::Error)
    end
  end

  describe Strands::Types::Exceptions::ModelThrottledError do
    it "can be raised with a throttle message" do
      expect {
        raise described_class, "Rate limit exceeded. Try again in 30s."
      }.to raise_error(described_class, /Rate limit exceeded/)
    end

    it "inherits from Strands::Error" do
      error = described_class.new("throttled")
      expect(error).to be_a(Strands::Error)
    end
  end

  describe Strands::Types::Exceptions::MaxTokensReachedError do
    it "can be raised when max tokens hit" do
      expect {
        raise described_class, "Maximum token limit reached"
      }.to raise_error(described_class, "Maximum token limit reached")
    end

    it "inherits from Strands::Error" do
      error = described_class.new("max tokens")
      expect(error).to be_a(Strands::Error)
    end
  end

  describe Strands::Types::Exceptions::MCPClientInitializationError do
    it "can be raised when MCP server fails" do
      expect {
        raise described_class, "Failed to connect to MCP server"
      }.to raise_error(described_class)
    end

    it "inherits from Strands::Error" do
      error = described_class.new("init failed")
      expect(error).to be_a(Strands::Error)
    end
  end

  describe Strands::Types::Exceptions::SessionError do
    it "can be raised for session failures" do
      expect {
        raise described_class, "Session expired"
      }.to raise_error(described_class, "Session expired")
    end

    it "inherits from Strands::Error" do
      expect(described_class.new).to be_a(Strands::Error)
    end
  end

  describe Strands::Types::Exceptions::StorageError do
    it "can be raised for storage failures" do
      expect {
        raise described_class, "S3 write failed"
      }.to raise_error(described_class, "S3 write failed")
    end

    it "inherits from Strands::Error" do
      expect(described_class.new).to be_a(Strands::Error)
    end
  end

  describe Strands::Types::Exceptions::AggregateMemoryError do
    it "wraps multiple errors" do
      errors = [RuntimeError.new("store1 failed"), RuntimeError.new("store2 failed")]
      error = described_class.new("Multiple memory stores failed", errors: errors)
      expect(error.message).to eq("Multiple memory stores failed")
      expect(error.errors).to eq(errors)
      expect(error.errors.size).to eq(2)
    end

    it "inherits from Strands::Error" do
      error = described_class.new("fail", errors: [])
      expect(error).to be_a(Strands::Error)
    end

    it "defaults to empty errors array" do
      error = described_class.new("no errors")
      expect(error.errors).to eq([])
    end
  end

  describe Strands::Types::Exceptions::ConcurrencyError do
    it "can be raised when concurrent access detected" do
      expect {
        raise described_class, "Agent already processing a request"
      }.to raise_error(described_class)
    end

    it "inherits from Strands::Error" do
      expect(described_class.new).to be_a(Strands::Error)
    end
  end

  describe Strands::Types::Exceptions::StructuredOutputError do
    it "can be raised for validation failures" do
      expect {
        raise described_class, "Output did not match schema after 3 retries"
      }.to raise_error(described_class)
    end

    it "inherits from Strands::Error" do
      expect(described_class.new).to be_a(Strands::Error)
    end
  end

  describe "all exceptions are rescuable as Strands::Error" do
    let(:exception_classes) do
      [
        Strands::Types::Exceptions::ContextWindowOverflowError,
        Strands::Types::Exceptions::ModelThrottledError,
        Strands::Types::Exceptions::MaxTokensReachedError,
        Strands::Types::Exceptions::MCPClientInitializationError,
        Strands::Types::Exceptions::SessionError,
        Strands::Types::Exceptions::SnapshotError,
        Strands::Types::Exceptions::ProviderTokenCountError,
        Strands::Types::Exceptions::ToolProviderError,
        Strands::Types::Exceptions::StructuredOutputError,
        Strands::Types::Exceptions::ConcurrencyError,
        Strands::Types::Exceptions::StorageError
      ]
    end

    it "all simple exceptions can be caught as Strands::Error" do
      exception_classes.each do |klass|
        expect {
          begin
            raise klass, "test"
          rescue Strands::Error
            # successfully caught
          end
        }.not_to raise_error
      end
    end
  end
end
