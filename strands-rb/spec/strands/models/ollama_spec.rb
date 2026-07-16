# frozen_string_literal: true

require "spec_helper"

RSpec.describe Strands::Models::Ollama do
  subject(:model) { described_class.new(model_id: "llama3", host: "http://localhost:11434") }

  describe "#initialize" do
    it "stores the model_id in config" do
      expect(model.config[:model_id]).to eq("llama3")
    end

    it "uses the provided host" do
      expect(model.config[:host]).to eq("http://localhost:11434")
    end

    it "uses default host when not specified" do
      m = described_class.new(model_id: "llama3")
      expect(m.config[:host]).to eq("http://localhost:11434")
    end

    it "stores additional params" do
      m = described_class.new(model_id: "llama3", temperature: 0.8, top_p: 0.9)
      expect(m.config[:params][:temperature]).to eq(0.8)
      expect(m.config[:params][:top_p]).to eq(0.9)
    end
  end

  describe "#update_config" do
    it "merges new options into config" do
      model.update_config(model_id: "mistral")
      expect(model.config[:model_id]).to eq("mistral")
    end
  end

  describe "#get_config" do
    it "returns a copy of the config" do
      config = model.get_config
      config[:model_id] = "modified"
      expect(model.config[:model_id]).to eq("llama3")
    end
  end

  describe "#format_request" do
    let(:messages) { [{ role: :user, content: [{ text: "Hello" }] }] }

    it "includes the model_id" do
      request = model.format_request(messages)
      expect(request[:model]).to eq("llama3")
    end

    it "sets stream to true" do
      request = model.format_request(messages)
      expect(request[:stream]).to be true
    end

    it "formats system prompt as first message" do
      request = model.format_request(messages, system_prompt: "Be helpful")
      system_msg = request[:messages].first
      expect(system_msg[:role]).to eq("system")
      expect(system_msg[:content]).to eq("Be helpful")
    end

    it "formats user message content" do
      request = model.format_request(messages)
      user_msg = request[:messages].first
      expect(user_msg[:content]).to eq("Hello")
    end

    it "includes options from params" do
      m = described_class.new(model_id: "llama3", temperature: 0.5, max_tokens: 1000)
      request = m.format_request(messages)
      expect(request[:options][:temperature]).to eq(0.5)
      expect(request[:options][:num_predict]).to eq(1000)
    end

    context "with tools" do
      let(:tools) do
        [
          Strands::Types::Tools::ToolSpec.new(
            name: "search",
            description: "Search the web",
            input_schema: { type: "object", properties: { query: { type: "string" } } }
          )
        ]
      end

      it "formats tool specs" do
        request = model.format_request(messages, tools: tools)
        expect(request[:tools].length).to eq(1)
        tool = request[:tools].first
        expect(tool[:type]).to eq("function")
        expect(tool[:function][:name]).to eq("search")
      end
    end
  end

  describe "#stream" do
    let(:messages) { [{ role: :user, content: [{ text: "Hello" }] }] }

    context "with a text-only response" do
      let(:streaming_response) do
        [
          JSON.generate({ model: "llama3", message: { role: "assistant", content: "Hi" }, done: false }),
          "\n",
          JSON.generate({ model: "llama3", message: { role: "assistant", content: " there" }, done: false }),
          "\n",
          JSON.generate({ model: "llama3", message: { role: "assistant", content: "" }, done: true,
                          prompt_eval_count: 15, eval_count: 8, total_duration: 500_000_000 }),
          "\n"
        ].join
      end

      before do
        stub_http_streaming(streaming_response)
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

      it "yields text deltas" do
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

      it "yields metadata with token counts" do
        events = collect_events(model, messages)
        metadata = events.find { |e| e.event_type == :metadata }
        expect(metadata.metadata.usage.input_tokens).to eq(15)
        expect(metadata.metadata.usage.output_tokens).to eq(8)
      end

      it "yields metadata with latency" do
        events = collect_events(model, messages)
        metadata = events.find { |e| e.event_type == :metadata }
        expect(metadata.metadata.metrics.latency_ms).to eq(500)
      end
    end

    context "with tool calls in response" do
      let(:streaming_response) do
        [
          JSON.generate({
            model: "llama3",
            message: {
              role: "assistant",
              content: "",
              tool_calls: [
                { function: { name: "calculator", arguments: { expr: "2+2" } } }
              ]
            },
            done: true,
            prompt_eval_count: 20,
            eval_count: 10,
            total_duration: 300_000_000
          }),
          "\n"
        ].join
      end

      before do
        stub_http_streaming(streaming_response)
      end

      it "yields tool use content blocks" do
        events = collect_events(model, messages)
        starts = events.select { |e| e.event_type == :content_block_start }
        tool_starts = starts.select { |e| e.content_block_start.start&.tool_use }
        expect(tool_starts.length).to eq(1)
        expect(tool_starts.first.content_block_start.start.tool_use.name).to eq("calculator")
      end

      it "yields tool input as delta" do
        events = collect_events(model, messages)
        deltas = events.select { |e| e.event_type == :content_block_delta }
        tool_deltas = deltas.select { |e| e.content_block_delta.delta.tool_use }
        expect(tool_deltas.length).to eq(1)
        input = tool_deltas.first.content_block_delta.delta.tool_use.input
        expect(JSON.parse(input)).to eq({ "expr" => "2+2" })
      end

      it "yields message_stop with tool_use reason" do
        events = collect_events(model, messages)
        msg_stop = events.find { |e| e.event_type == :message_stop }
        expect(msg_stop.message_stop.stop_reason).to eq(:tool_use)
      end
    end

    context "with context overflow error" do
      before do
        stub_http_error(400, { error: "the prompt is longer than the context length" })
      end

      it "raises ContextWindowOverflowError" do
        expect {
          collect_events(model, messages)
        }.to raise_error(Strands::Types::Exceptions::ContextWindowOverflowError)
      end
    end

    context "with server overload (503)" do
      before do
        stub_http_error(503, { error: "server busy" })
      end

      it "raises ModelThrottledError" do
        expect {
          collect_events(model, messages)
        }.to raise_error(Strands::Types::Exceptions::ModelThrottledError)
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
