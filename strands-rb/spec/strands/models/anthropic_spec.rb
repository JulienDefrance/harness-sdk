# frozen_string_literal: true

require "spec_helper"

RSpec.describe Strands::Models::Anthropic do
  subject(:model) do
    described_class.new(
      model_id: "claude-3-5-sonnet-20241022",
      max_tokens: 4096,
      api_key: "test-anthropic-key"
    )
  end

  describe "#initialize" do
    it "stores the model_id in config" do
      expect(model.config[:model_id]).to eq("claude-3-5-sonnet-20241022")
    end

    it "stores the max_tokens in config" do
      expect(model.config[:max_tokens]).to eq(4096)
    end

    it "stores the api_key in config" do
      expect(model.config[:api_key]).to eq("test-anthropic-key")
    end

    it "uses default base_url" do
      expect(model.config[:base_url]).to eq("https://api.anthropic.com")
    end

    it "reads api_key from ENV when not provided" do
      allow(ENV).to receive(:fetch).with("ANTHROPIC_API_KEY", nil).and_return("env-api-key")
      m = described_class.new(model_id: "claude-3-5-sonnet-20241022")
      expect(m.config[:api_key]).to eq("env-api-key")
    end

    it "allows overriding the base_url" do
      m = described_class.new(
        model_id: "claude-3-5-sonnet-20241022",
        api_key: "key",
        base_url: "https://custom.api.example.com"
      )
      expect(m.config[:base_url]).to eq("https://custom.api.example.com")
    end

    it "stores additional params" do
      m = described_class.new(model_id: "claude-3-5-sonnet-20241022", api_key: "key", temperature: 0.5)
      expect(m.config[:params][:temperature]).to eq(0.5)
    end
  end

  describe "#update_config" do
    it "merges new options into config" do
      model.update_config(model_id: "claude-3-haiku-20240307")
      expect(model.config[:model_id]).to eq("claude-3-haiku-20240307")
    end
  end

  describe "#get_config" do
    it "returns a copy of the config" do
      config = model.get_config
      config[:model_id] = "modified"
      expect(model.config[:model_id]).to eq("claude-3-5-sonnet-20241022")
    end
  end

  describe "#inspect" do
    it "shows model_id and base_url" do
      result = model.inspect
      expect(result).to include("model_id")
      expect(result).to include("claude-3-5-sonnet-20241022")
      expect(result).to include("base_url")
    end

    it "does not expose the api_key" do
      result = model.inspect
      expect(result).not_to include("test-anthropic-key")
    end
  end

  describe "#format_request" do
    let(:messages) { [{ role: :user, content: [{ text: "Hello" }] }] }

    it "includes the model_id" do
      request = model.format_request(messages)
      expect(request[:model]).to eq("claude-3-5-sonnet-20241022")
    end

    it "includes max_tokens" do
      request = model.format_request(messages)
      expect(request[:max_tokens]).to eq(4096)
    end

    it "sets stream to true" do
      request = model.format_request(messages)
      expect(request[:stream]).to be true
    end

    it "formats messages with role and content" do
      request = model.format_request(messages)
      msg = request[:messages].first
      expect(msg[:role]).to eq("user")
      expect(msg[:content]).to include({ type: "text", text: "Hello" })
    end

    it "includes system prompt when provided" do
      request = model.format_request(messages, system_prompt: "Be helpful")
      expect(request[:system]).to eq("Be helpful")
    end

    it "does not include system when nil" do
      request = model.format_request(messages)
      expect(request).not_to have_key(:system)
    end

    context "with tools" do
      let(:tools) do
        [
          Strands::Types::Tools::ToolSpec.new(
            name: "calculator",
            description: "Do math",
            input_schema: { type: "object", properties: { expr: { type: "string" } } }
          )
        ]
      end

      it "formats tool specs" do
        request = model.format_request(messages, tools: tools)
        expect(request[:tools].length).to eq(1)
        tool = request[:tools].first
        expect(tool[:name]).to eq("calculator")
        expect(tool[:description]).to eq("Do math")
        expect(tool[:input_schema]).to eq({ type: "object", properties: { expr: { type: "string" } } })
      end
    end

    context "with tool_choice" do
      it "formats ToolChoiceAuto" do
        request = model.format_request(messages, tool_choice: Strands::Types::Tools::ToolChoiceAuto.new)
        expect(request[:tool_choice]).to eq({ type: "auto" })
      end

      it "formats ToolChoiceAny" do
        request = model.format_request(messages, tool_choice: Strands::Types::Tools::ToolChoiceAny.new)
        expect(request[:tool_choice]).to eq({ type: "any" })
      end

      it "formats ToolChoiceTool" do
        choice = Strands::Types::Tools::ToolChoiceTool.new(name: "calc")
        request = model.format_request(messages, tool_choice: choice)
        expect(request[:tool_choice]).to eq({ type: "tool", name: "calc" })
      end
    end

    context "with tool use and results in messages" do
      let(:messages) do
        [
          { role: :assistant, content: [
            { text: "Let me calculate." },
            { tool_use: { name: "calc", tool_use_id: "tu_1", input: { expr: "2+2" } } }
          ] },
          { role: :user, content: [
            { tool_result: { tool_use_id: "tu_1", content: [{ text: "4" }], status: :success } }
          ] }
        ]
      end

      it "formats assistant message with tool_use block" do
        request = model.format_request(messages)
        assistant_msg = request[:messages].first
        tool_use_block = assistant_msg[:content].find { |b| b[:type] == "tool_use" }
        expect(tool_use_block[:name]).to eq("calc")
        expect(tool_use_block[:id]).to eq("tu_1")
        expect(tool_use_block[:input]).to eq({ expr: "2+2" })
      end

      it "formats tool result as tool_result block" do
        request = model.format_request(messages)
        user_msg = request[:messages].last
        tool_result_block = user_msg[:content].find { |b| b[:type] == "tool_result" }
        expect(tool_result_block[:tool_use_id]).to eq("tu_1")
        expect(tool_result_block[:content]).to include({ type: "text", text: "4" })
      end
    end
  end

  describe "#stream" do
    let(:messages) { [{ role: :user, content: [{ text: "Hello" }] }] }

    context "with a successful text response" do
      let(:sse_response) do
        [
          "data: #{JSON.generate({ type: "message_start", message: { role: "assistant", usage: { input_tokens: 10, output_tokens: 0 } } })}\n\n",
          "data: #{JSON.generate({ type: "content_block_start", index: 0, content_block: { type: "text", text: "" } })}\n\n",
          "data: #{JSON.generate({ type: "content_block_delta", index: 0, delta: { type: "text_delta", text: "Hello" } })}\n\n",
          "data: #{JSON.generate({ type: "content_block_delta", index: 0, delta: { type: "text_delta", text: " world" } })}\n\n",
          "data: #{JSON.generate({ type: "content_block_stop", index: 0 })}\n\n",
          "data: #{JSON.generate({ type: "message_delta", delta: { stop_reason: "end_turn" }, usage: { output_tokens: 5 } })}\n\n"
        ].join
      end

      before do
        stub_http_streaming(sse_response)
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

      it "yields metadata event with usage from message_delta" do
        events = collect_events(model, messages)
        metadata_events = events.select { |e| e.event_type == :metadata }
        output_usage = metadata_events.find { |e| e.metadata.usage.output_tokens == 5 }
        expect(output_usage).not_to be_nil
      end
    end

    context "with tool use in response" do
      let(:sse_response) do
        [
          "data: #{JSON.generate({ type: "message_start", message: { role: "assistant", usage: { input_tokens: 15, output_tokens: 0 } } })}\n\n",
          "data: #{JSON.generate({ type: "content_block_start", index: 0, content_block: { type: "tool_use", id: "tu_123", name: "calculator" } })}\n\n",
          "data: #{JSON.generate({ type: "content_block_delta", index: 0, delta: { type: "input_json_delta", partial_json: "{\"expr\":" } })}\n\n",
          "data: #{JSON.generate({ type: "content_block_delta", index: 0, delta: { type: "input_json_delta", partial_json: "\"2+2\"}" } })}\n\n",
          "data: #{JSON.generate({ type: "content_block_stop", index: 0 })}\n\n",
          "data: #{JSON.generate({ type: "message_delta", delta: { stop_reason: "tool_use" }, usage: { output_tokens: 12 } })}\n\n"
        ].join
      end

      before do
        stub_http_streaming(sse_response)
      end

      it "yields tool use content block start" do
        events = collect_events(model, messages)
        starts = events.select { |e| e.event_type == :content_block_start }
        tool_starts = starts.select { |e| e.content_block_start.start&.tool_use }
        expect(tool_starts.length).to eq(1)
        expect(tool_starts.first.content_block_start.start.tool_use.name).to eq("calculator")
        expect(tool_starts.first.content_block_start.start.tool_use.tool_use_id).to eq("tu_123")
      end

      it "yields input_json_delta as tool use delta" do
        events = collect_events(model, messages)
        deltas = events.select { |e| e.event_type == :content_block_delta }
        tool_deltas = deltas.select { |e| e.content_block_delta.delta.tool_use }
        inputs = tool_deltas.map { |e| e.content_block_delta.delta.tool_use.input }
        expect(inputs).to eq(["{\"expr\":", "\"2+2\"}"])
      end

      it "yields message_stop with tool_use reason" do
        events = collect_events(model, messages)
        msg_stop = events.find { |e| e.event_type == :message_stop }
        expect(msg_stop.message_stop.stop_reason).to eq(:tool_use)
      end
    end

    context "with rate limit error (429)" do
      before do
        stub_http_error(429, { error: { message: "Rate limit exceeded" } })
      end

      it "raises ModelThrottledError" do
        expect {
          collect_events(model, messages)
        }.to raise_error(Strands::Types::Exceptions::ModelThrottledError, /Rate limit exceeded/)
      end
    end

    context "with overloaded error (529)" do
      before do
        stub_http_error(529, { error: { message: "API is temporarily overloaded" } })
      end

      it "raises ModelThrottledError" do
        expect {
          collect_events(model, messages)
        }.to raise_error(Strands::Types::Exceptions::ModelThrottledError, /overloaded/)
      end
    end

    context "with context window overflow (400)" do
      before do
        stub_http_error(400, { error: { message: "prompt is too long: 200000 tokens > 100000 maximum" } })
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
