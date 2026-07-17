# frozen_string_literal: true

require "spec_helper"

RSpec.describe Strands::Models::Gemini do
  subject(:model) { described_class.new(model_id: "gemini-1.5-pro", api_key: "test-gemini-key") }

  describe "#initialize" do
    it "stores the model_id in config" do
      expect(model.config[:model_id]).to eq("gemini-1.5-pro")
    end

    it "stores the api_key in config" do
      expect(model.config[:api_key]).to eq("test-gemini-key")
    end

    it "stores additional params" do
      m = described_class.new(model_id: "gemini-1.5-pro", api_key: "key", temperature: 0.5)
      expect(m.config[:params][:temperature]).to eq(0.5)
    end
  end

  describe "#update_config" do
    it "merges new options into config" do
      model.update_config(model_id: "gemini-1.5-flash")
      expect(model.config[:model_id]).to eq("gemini-1.5-flash")
    end
  end

  describe "#get_config" do
    it "returns a copy of the config" do
      config = model.get_config
      config[:model_id] = "modified"
      expect(model.config[:model_id]).to eq("gemini-1.5-pro")
    end
  end

  describe "#inspect" do
    it "includes model_id" do
      expect(model.inspect).to include("gemini-1.5-pro")
    end

    it "does not include api_key" do
      expect(model.inspect).not_to include("test-gemini-key")
    end
  end

  describe "#format_request" do
    let(:messages) { [{ role: :user, content: [{ text: "Hello" }] }] }

    it "formats contents in Gemini format" do
      request = model.format_request(messages)
      expect(request[:contents]).to be_an(Array)
      expect(request[:contents][0][:role]).to eq("user")
      expect(request[:contents][0][:parts]).to include({ text: "Hello" })
    end

    it "includes system instruction when provided" do
      request = model.format_request(messages, system_prompt: "Be helpful")
      expect(request[:systemInstruction]).to eq({ parts: [{ text: "Be helpful" }] })
    end

    it "includes generation config from params" do
      m = described_class.new(model_id: "gemini-1.5-pro", api_key: "k", temperature: 0.7, max_tokens: 100)
      request = m.format_request(messages)
      expect(request[:generationConfig][:temperature]).to eq(0.7)
      expect(request[:generationConfig][:maxOutputTokens]).to eq(100)
    end

    context "with tools" do
      let(:tools) do
        [Strands::Types::Tools::ToolSpec.new(
          name: "calculator",
          description: "Do math",
          input_schema: { type: "object", properties: { expr: { type: "string" } } }
        )]
      end

      it "formats tools as functionDeclarations" do
        request = model.format_request(messages, tools: tools)
        expect(request[:tools]).to eq([{
          functionDeclarations: [{
            name: "calculator",
            description: "Do math",
            parameters: { type: "object", properties: { expr: { type: "string" } } }
          }]
        }])
      end
    end
  end

  describe "#stream" do
    let(:messages) { [{ role: :user, content: [{ text: "Hello" }] }] }

    context "with a successful text response" do
      let(:sse_response) do
        [
          "data: #{JSON.generate({ candidates: [{ content: { parts: [{ text: "Hi" }] } }] })}\n\n",
          "data: #{JSON.generate({ candidates: [{ content: { parts: [{ text: " there" }] }, finishReason: "STOP" }], usageMetadata: { promptTokenCount: 5, candidatesTokenCount: 3, totalTokenCount: 8 } })}\n\n"
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
        expect(texts).to eq(["Hi", " there"])
      end

      it "yields message_stop with end_turn" do
        events = collect_events(model, messages)
        msg_stop = events.find { |e| e.event_type == :message_stop }
        expect(msg_stop.message_stop.stop_reason).to eq(:end_turn)
      end

      it "yields metadata with usage" do
        events = collect_events(model, messages)
        metadata = events.find { |e| e.event_type == :metadata }
        expect(metadata.metadata.usage.input_tokens).to eq(5)
        expect(metadata.metadata.usage.output_tokens).to eq(3)
      end
    end

    context "with function calls in response" do
      let(:sse_response) do
        [
          "data: #{JSON.generate({ candidates: [{ content: { parts: [{ functionCall: { name: "calc", args: { expr: "2+2" } } }] }, finishReason: "STOP" }] })}\n\n"
        ].join
      end

      before { stub_http_streaming(sse_response) }

      it "yields tool use content blocks" do
        events = collect_events(model, messages)
        starts = events.select { |e| e.event_type == :content_block_start }
        tool_starts = starts.select { |e| e.content_block_start.start&.tool_use }
        expect(tool_starts.length).to eq(1)
        expect(tool_starts.first.content_block_start.start.tool_use.name).to eq("calc")
      end

      it "yields message_stop with tool_use reason" do
        events = collect_events(model, messages)
        msg_stop = events.find { |e| e.event_type == :message_stop }
        expect(msg_stop.message_stop.stop_reason).to eq(:tool_use)
      end
    end

    context "with rate limit error" do
      before { stub_http_error(429, { error: { message: "Rate limit exceeded" } }) }

      it "raises ModelThrottledError" do
        expect {
          collect_events(model, messages)
        }.to raise_error(Strands::Types::Exceptions::ModelThrottledError)
      end
    end

    context "with context overflow error" do
      before { stub_http_error(400, { error: { message: "The request is too large" } }) }

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
