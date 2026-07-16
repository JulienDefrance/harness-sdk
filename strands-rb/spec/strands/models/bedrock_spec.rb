# frozen_string_literal: true

require "spec_helper"

RSpec.describe Strands::Models::Bedrock do
  subject(:model) do
    described_class.new(
      model_id: "anthropic.claude-3-5-sonnet-20241022-v2:0",
      region: "us-west-2",
      access_key_id: "AKIAIOSFODNN7EXAMPLE",
      secret_access_key: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
    )
  end

  describe "#initialize" do
    it "stores the model_id in config" do
      expect(model.config[:model_id]).to eq("anthropic.claude-3-5-sonnet-20241022-v2:0")
    end

    it "stores the region in config" do
      expect(model.config[:region]).to eq("us-west-2")
    end

    it "stores AWS credentials in config" do
      expect(model.config[:access_key_id]).to eq("AKIAIOSFODNN7EXAMPLE")
      expect(model.config[:secret_access_key]).to eq("wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY")
    end

    it "uses default region when not specified" do
      m = described_class.new(
        model_id: "anthropic.claude-3-5-sonnet-20241022-v2:0",
        access_key_id: "key",
        secret_access_key: "secret"
      )
      expect(m.config[:region]).to eq("us-west-2")
    end

    it "reads credentials from environment when not provided" do
      allow(ENV).to receive(:fetch).with("AWS_REGION", anything).and_return("us-east-1")
      allow(ENV).to receive(:fetch).with("AWS_DEFAULT_REGION", "us-west-2").and_return("us-east-1")
      allow(ENV).to receive(:fetch).with("AWS_ACCESS_KEY_ID", nil).and_return("env-key")
      allow(ENV).to receive(:fetch).with("AWS_SECRET_ACCESS_KEY", nil).and_return("env-secret")
      allow(ENV).to receive(:fetch).with("AWS_SESSION_TOKEN", nil).and_return(nil)

      m = described_class.new(model_id: "anthropic.claude-3-5-sonnet-20241022-v2:0")
      expect(m.config[:access_key_id]).to eq("env-key")
      expect(m.config[:secret_access_key]).to eq("env-secret")
    end

    it "stores session_token when provided" do
      m = described_class.new(
        model_id: "anthropic.claude-3-5-sonnet-20241022-v2:0",
        access_key_id: "key",
        secret_access_key: "secret",
        session_token: "session-token-123"
      )
      expect(m.config[:session_token]).to eq("session-token-123")
    end

    it "stores additional params" do
      m = described_class.new(
        model_id: "anthropic.claude-3-5-sonnet-20241022-v2:0",
        access_key_id: "key",
        secret_access_key: "secret",
        max_tokens: 2048,
        temperature: 0.7
      )
      expect(m.config[:params][:max_tokens]).to eq(2048)
      expect(m.config[:params][:temperature]).to eq(0.7)
    end
  end

  describe "#update_config" do
    it "merges new options into config" do
      model.update_config(model_id: "anthropic.claude-3-haiku-20240307-v1:0")
      expect(model.config[:model_id]).to eq("anthropic.claude-3-haiku-20240307-v1:0")
    end
  end

  describe "#get_config" do
    it "returns a copy of the config" do
      config = model.get_config
      config[:model_id] = "modified"
      expect(model.config[:model_id]).to eq("anthropic.claude-3-5-sonnet-20241022-v2:0")
    end
  end

  describe "#inspect" do
    it "shows model_id and region" do
      result = model.inspect
      expect(result).to include("model_id")
      expect(result).to include("anthropic.claude-3-5-sonnet-20241022-v2:0")
      expect(result).to include("region")
      expect(result).to include("us-west-2")
    end

    it "does not expose credentials" do
      result = model.inspect
      expect(result).not_to include("wJalrXUtnFEMI")
      expect(result).not_to include("AKIAIOSFODNN7EXAMPLE")
    end
  end

  describe "#stream" do
    let(:messages) { [{ role: :user, content: [{ text: "Hello" }] }] }

    # Force the HTTP path by ensuring @use_sdk is false
    before do
      model.instance_variable_set(:@use_sdk, false)
    end

    context "with a successful text response" do
      let(:event_stream_body) do
        [
          '{"messageStart":{"role":"assistant"}}',
          '{"contentBlockStart":{"start":{}}}',
          '{"contentBlockDelta":{"delta":{"text":"Hello"}}}',
          '{"contentBlockDelta":{"delta":{"text":" world"}}}',
          '{"contentBlockStop":{}}',
          '{"messageStop":{"stopReason":"end_turn"}}',
          '{"metadata":{"usage":{"inputTokens":10,"outputTokens":5},"metrics":{"latencyMs":200}}}'
        ].join
      end

      before do
        stub_http_streaming(event_stream_body)
      end

      it "yields message_start event" do
        events = collect_events(model, messages)
        expect(events.first.event_type).to eq(:message_start)
        expect(events.first.message_start.role).to eq(:assistant)
      end

      it "yields content_block_start event" do
        events = collect_events(model, messages)
        starts = events.select { |e| e.event_type == :content_block_start }
        expect(starts.length).to eq(1)
      end

      it "yields content_block_delta events with text" do
        events = collect_events(model, messages)
        deltas = events.select { |e| e.event_type == :content_block_delta }
        texts = deltas.map { |e| e.content_block_delta.delta.text }.compact
        expect(texts).to eq(["Hello", " world"])
      end

      it "yields content_block_stop event" do
        events = collect_events(model, messages)
        stops = events.select { |e| e.event_type == :content_block_stop }
        expect(stops.length).to eq(1)
      end

      it "yields message_stop event with end_turn" do
        events = collect_events(model, messages)
        msg_stop = events.find { |e| e.event_type == :message_stop }
        expect(msg_stop.message_stop.stop_reason).to eq(:end_turn)
      end

      it "yields metadata event with usage" do
        events = collect_events(model, messages)
        metadata = events.find { |e| e.event_type == :metadata }
        expect(metadata.metadata.usage.input_tokens).to eq(10)
        expect(metadata.metadata.usage.output_tokens).to eq(5)
      end

      it "yields metadata event with metrics" do
        events = collect_events(model, messages)
        metadata = events.find { |e| e.event_type == :metadata }
        expect(metadata.metadata.metrics.latency_ms).to eq(200)
      end
    end

    context "with tool use in response" do
      let(:event_stream_body) do
        [
          '{"messageStart":{"role":"assistant"}}',
          '{"contentBlockStart":{"start":{"toolUse":{"name":"calculator","toolUseId":"tool_1"}}}}',
          '{"contentBlockDelta":{"delta":{"toolUse":{"input":"{\"expr\":\"2+2\"}"}}}}',
          '{"contentBlockStop":{}}',
          '{"messageStop":{"stopReason":"tool_use"}}',
          '{"metadata":{"usage":{"inputTokens":20,"outputTokens":10}}}'
        ].join
      end

      before do
        stub_http_streaming(event_stream_body)
      end

      it "yields tool use content block start" do
        events = collect_events(model, messages)
        starts = events.select { |e| e.event_type == :content_block_start }
        tool_starts = starts.select { |e| e.content_block_start.start&.tool_use }
        expect(tool_starts.length).to eq(1)
        expect(tool_starts.first.content_block_start.start.tool_use.name).to eq("calculator")
        expect(tool_starts.first.content_block_start.start.tool_use.tool_use_id).to eq("tool_1")
      end

      it "yields tool input delta" do
        events = collect_events(model, messages)
        deltas = events.select { |e| e.event_type == :content_block_delta }
        tool_deltas = deltas.select { |e| e.content_block_delta.delta.tool_use }
        expect(tool_deltas.length).to eq(1)
        expect(tool_deltas.first.content_block_delta.delta.tool_use.input).to eq("{\"expr\":\"2+2\"}")
      end

      it "yields message_stop with tool_use reason" do
        events = collect_events(model, messages)
        msg_stop = events.find { |e| e.event_type == :message_stop }
        expect(msg_stop.message_stop.stop_reason).to eq(:tool_use)
      end
    end

    context "with rate limit error (429)" do
      before do
        stub_http_error(429, { message: "Too many requests" })
      end

      it "raises ModelThrottledError" do
        expect {
          collect_events(model, messages)
        }.to raise_error(Strands::Types::Exceptions::ModelThrottledError, /Too many requests/)
      end
    end

    context "with context window overflow (400)" do
      before do
        stub_http_error(400, { message: "Input is too long for requested model" })
      end

      it "raises ContextWindowOverflowError" do
        expect {
          collect_events(model, messages)
        }.to raise_error(Strands::Types::Exceptions::ContextWindowOverflowError)
      end
    end
  end

  # Helper methods for specs

  def collect_events(model, messages)
    events = []
    model.stream(messages) { |e| events << e }
    events
  end

  def stub_http_streaming(response_body)
    mock_response = instance_double(Net::HTTPOK, is_a?: true)
    allow(mock_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
    allow(mock_response).to receive(:read_body).and_yield(response_body)

    mock_http = instance_double(Net::HTTP)
    allow(mock_http).to receive(:use_ssl=)
    allow(mock_http).to receive(:read_timeout=)
    allow(mock_http).to receive(:request).and_yield(mock_response)

    allow(Net::HTTP).to receive(:new).and_return(mock_http)
  end

  def stub_http_error(code, body)
    mock_response = instance_double(Net::HTTPResponse)
    allow(mock_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(false)
    allow(mock_response).to receive(:code).and_return(code.to_s)
    allow(mock_response).to receive(:body).and_return(JSON.generate(body))

    mock_http = instance_double(Net::HTTP)
    allow(mock_http).to receive(:use_ssl=)
    allow(mock_http).to receive(:read_timeout=)
    allow(mock_http).to receive(:request).and_yield(mock_response)

    allow(Net::HTTP).to receive(:new).and_return(mock_http)
  end
end
