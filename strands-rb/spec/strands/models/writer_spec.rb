# frozen_string_literal: true

require "spec_helper"

RSpec.describe Strands::Models::Writer do
  subject(:model) { described_class.new(model_id: "palmyra-x-004", api_key: "test-writer-key") }

  describe "#initialize" do
    it "stores the model_id in config" do
      expect(model.config[:model_id]).to eq("palmyra-x-004")
    end

    it "stores the api_key in config" do
      expect(model.config[:api_key]).to eq("test-writer-key")
    end

    it "uses default base_url" do
      expect(model.config[:base_url]).to eq("https://api.writer.com")
    end

    it "stores additional params" do
      m = described_class.new(model_id: "palmyra-x-004", api_key: "key", temperature: 0.8)
      expect(m.config[:params][:temperature]).to eq(0.8)
    end
  end

  describe "#update_config" do
    it "merges new options into config" do
      model.update_config(model_id: "palmyra-x-003")
      expect(model.config[:model_id]).to eq("palmyra-x-003")
    end
  end

  describe "#get_config" do
    it "returns a copy of the config" do
      config = model.get_config
      config[:model_id] = "modified"
      expect(model.config[:model_id]).to eq("palmyra-x-004")
    end
  end

  describe "#format_request" do
    let(:messages) { [{ role: :user, content: [{ text: "Hello" }] }] }

    it "includes the model_id" do
      request = model.format_request(messages)
      expect(request[:model]).to eq("palmyra-x-004")
    end

    it "sets stream to true" do
      request = model.format_request(messages)
      expect(request[:stream]).to be true
    end

    it "formats system prompt as system message" do
      request = model.format_request(messages, system_prompt: "Be helpful")
      expect(request[:messages].first[:role]).to eq("system")
      expect(request[:messages].first[:content]).to eq("Be helpful")
    end
  end

  describe "#stream" do
    let(:messages) { [{ role: :user, content: [{ text: "Hello" }] }] }

    context "with a successful text response" do
      let(:sse_response) do
        [
          "data: #{JSON.generate({ choices: [{ delta: { content: "Hello" }, index: 0 }] })}\n\n",
          "data: #{JSON.generate({ choices: [{ delta: { content: " there" }, index: 0 }] })}\n\n",
          "data: #{JSON.generate({ choices: [{ delta: {}, finish_reason: "stop", index: 0 }] })}\n\n",
          "data: [DONE]\n\n"
        ].join
      end

      before { stub_http_streaming(sse_response) }

      it "yields message_start event" do
        events = collect_events(model, messages)
        expect(events.first.event_type).to eq(:message_start)
      end

      it "yields content_block_delta events with text" do
        events = collect_events(model, messages)
        deltas = events.select { |e| e.event_type == :content_block_delta }
        texts = deltas.map { |e| e.content_block_delta.delta.text }.compact
        expect(texts).to eq(["Hello", " there"])
      end

      it "yields message_stop with end_turn" do
        events = collect_events(model, messages)
        msg_stop = events.find { |e| e.event_type == :message_stop }
        expect(msg_stop.message_stop.stop_reason).to eq(:end_turn)
      end
    end

    context "with tool calls" do
      let(:sse_response) do
        [
          "data: #{JSON.generate({ choices: [{ delta: { tool_calls: [{ index: 0, id: "call_w1", function: { name: "search", arguments: "" } }] }, index: 0 }] })}\n\n",
          "data: #{JSON.generate({ choices: [{ delta: { tool_calls: [{ index: 0, function: { arguments: '{"q":"hello"}' } }] }, index: 0 }] })}\n\n",
          "data: #{JSON.generate({ choices: [{ delta: {}, finish_reason: "tool_calls", index: 0 }] })}\n\n",
          "data: [DONE]\n\n"
        ].join
      end

      before { stub_http_streaming(sse_response) }

      it "yields tool use blocks" do
        events = collect_events(model, messages)
        starts = events.select { |e| e.event_type == :content_block_start }
        tool_starts = starts.select { |e| e.content_block_start.start&.tool_use }
        expect(tool_starts.length).to eq(1)
        expect(tool_starts.first.content_block_start.start.tool_use.name).to eq("search")
      end

      it "yields message_stop with tool_use reason" do
        events = collect_events(model, messages)
        msg_stop = events.find { |e| e.event_type == :message_stop }
        expect(msg_stop.message_stop.stop_reason).to eq(:tool_use)
      end
    end

    context "with rate limit error" do
      before { stub_http_error(429, { error: { message: "Rate limited" } }) }

      it "raises ModelThrottledError" do
        expect {
          collect_events(model, messages)
        }.to raise_error(Strands::Types::Exceptions::ModelThrottledError)
      end
    end

    context "with context overflow error" do
      before { stub_http_error(400, { error: { message: "maximum context length exceeded" } }) }

      it "raises ContextWindowOverflowError" do
        expect {
          collect_events(model, messages)
        }.to raise_error(Strands::Types::Exceptions::ContextWindowOverflowError)
      end
    end
  end

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
