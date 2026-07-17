# frozen_string_literal: true

require "spec_helper"

RSpec.describe Strands::Models::OpenAI do
  subject(:model) { described_class.new(model_id: "gpt-4o", api_key: "test-api-key") }

  describe "#initialize" do
    it "stores the model_id in config" do
      expect(model.config[:model_id]).to eq("gpt-4o")
    end

    it "stores the api_key in config" do
      expect(model.config[:api_key]).to eq("test-api-key")
    end

    it "uses default base_url" do
      expect(model.config[:base_url]).to eq("https://api.openai.com")
    end

    it "stores additional params" do
      m = described_class.new(model_id: "gpt-4o", api_key: "key", temperature: 0.7)
      expect(m.config[:params][:temperature]).to eq(0.7)
    end
  end

  describe "#update_config" do
    it "merges new options into config" do
      model.update_config(model_id: "gpt-4o-mini")
      expect(model.config[:model_id]).to eq("gpt-4o-mini")
    end
  end

  describe "#get_config" do
    it "returns a copy of the config" do
      config = model.get_config
      config[:model_id] = "modified"
      expect(model.config[:model_id]).to eq("gpt-4o")
    end
  end

  describe "#format_request" do
    let(:messages) { [{ role: :user, content: [{ text: "Hello" }] }] }

    it "includes the model_id" do
      request = model.format_request(messages)
      expect(request[:model]).to eq("gpt-4o")
    end

    it "sets stream to true" do
      request = model.format_request(messages)
      expect(request[:stream]).to be true
    end

    it "includes stream_options" do
      request = model.format_request(messages)
      expect(request[:stream_options]).to eq({ include_usage: true })
    end

    it "formats system prompt as system message" do
      request = model.format_request(messages, system_prompt: "Be helpful")
      system_msg = request[:messages].first
      expect(system_msg[:role]).to eq("system")
      expect(system_msg[:content]).to eq("Be helpful")
    end

    it "formats text content" do
      request = model.format_request(messages)
      user_msg = request[:messages].first
      expect(user_msg[:content]).to include({ type: "text", text: "Hello" })
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
        expect(tool[:type]).to eq("function")
        expect(tool[:function][:name]).to eq("calculator")
        expect(tool[:function][:description]).to eq("Do math")
      end
    end

    context "with tool_choice" do
      it "formats ToolChoiceAuto" do
        request = model.format_request(messages, tool_choice: Strands::Types::Tools::ToolChoiceAuto.new)
        expect(request[:tool_choice]).to eq("auto")
      end

      it "formats ToolChoiceAny as required" do
        request = model.format_request(messages, tool_choice: Strands::Types::Tools::ToolChoiceAny.new)
        expect(request[:tool_choice]).to eq("required")
      end

      it "formats ToolChoiceTool" do
        choice = Strands::Types::Tools::ToolChoiceTool.new(name: "calc")
        request = model.format_request(messages, tool_choice: choice)
        expect(request[:tool_choice]).to eq({ type: "function", function: { name: "calc" } })
      end
    end

    context "with tool use and results in messages" do
      let(:messages) do
        [
          { role: :assistant, content: [
            { text: "I'll calculate." },
            { tool_use: { name: "calc", tool_use_id: "tu_1", input: { expr: "2+2" } } }
          ] },
          { role: :user, content: [
            { tool_result: { tool_use_id: "tu_1", content: [{ text: "4" }], status: :success } }
          ] }
        ]
      end

      it "formats assistant message with tool_calls" do
        request = model.format_request(messages)
        assistant_msg = request[:messages].first
        expect(assistant_msg[:tool_calls].length).to eq(1)
        expect(assistant_msg[:tool_calls].first[:function][:name]).to eq("calc")
      end

      it "formats tool result as tool message" do
        request = model.format_request(messages)
        tool_msg = request[:messages].last
        expect(tool_msg[:role]).to eq("tool")
        expect(tool_msg[:tool_call_id]).to eq("tu_1")
        expect(tool_msg[:content]).to eq("4")
      end
    end
  end

  describe "#stream" do
    let(:messages) { [{ role: :user, content: [{ text: "Hello" }] }] }

    context "with a successful text response" do
      let(:sse_response) do
        [
          "data: #{JSON.generate({ choices: [{ delta: { content: "Hello" }, index: 0 }] })}\n\n",
          "data: #{JSON.generate({ choices: [{ delta: { content: " world" }, index: 0 }] })}\n\n",
          "data: #{JSON.generate({ choices: [{ delta: {}, finish_reason: "stop", index: 0 }] })}\n\n",
          "data: #{JSON.generate({ choices: [], usage: { prompt_tokens: 10, completion_tokens: 5, total_tokens: 15 } })}\n\n",
          "data: [DONE]\n\n"
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

      it "yields metadata event with usage" do
        events = collect_events(model, messages)
        metadata = events.find { |e| e.event_type == :metadata }
        expect(metadata.metadata.usage.input_tokens).to eq(10)
        expect(metadata.metadata.usage.output_tokens).to eq(5)
      end
    end

    context "with tool calls in response" do
      let(:sse_response) do
        [
          "data: #{JSON.generate({ choices: [{ delta: { tool_calls: [{ index: 0, id: 'call_123', function: { name: 'calc', arguments: '' } }] }, index: 0 }] })}\n\n",
          "data: #{JSON.generate({ choices: [{ delta: { tool_calls: [{ index: 0, function: { arguments: '{\"ex' } }] }, index: 0 }] })}\n\n",
          "data: #{JSON.generate({ choices: [{ delta: { tool_calls: [{ index: 0, function: { arguments: 'pr\":\"2+2\"}' } }] }, index: 0 }] })}\n\n",
          "data: #{JSON.generate({ choices: [{ delta: {}, finish_reason: "tool_calls", index: 0 }] })}\n\n",
          "data: [DONE]\n\n"
        ].join
      end

      before do
        stub_http_streaming(sse_response)
      end

      it "yields tool use content blocks" do
        events = collect_events(model, messages)
        starts = events.select { |e| e.event_type == :content_block_start }
        tool_starts = starts.select { |e| e.content_block_start.start&.tool_use }
        expect(tool_starts.length).to eq(1)
        expect(tool_starts.first.content_block_start.start.tool_use.name).to eq("calc")
        expect(tool_starts.first.content_block_start.start.tool_use.tool_use_id).to eq("call_123")
      end

      it "yields tool input delta" do
        events = collect_events(model, messages)
        deltas = events.select { |e| e.event_type == :content_block_delta }
        tool_deltas = deltas.select { |e| e.content_block_delta.delta.tool_use }
        input = tool_deltas.map { |e| e.content_block_delta.delta.tool_use.input }.join
        expect(input).to eq('{\"expr\":\"2+2\"}')
      end

      it "yields message_stop with tool_use reason" do
        events = collect_events(model, messages)
        msg_stop = events.find { |e| e.event_type == :message_stop }
        expect(msg_stop.message_stop.stop_reason).to eq(:tool_use)
      end
    end

    context "with rate limit error" do
      before do
        stub_http_error(429, { error: { message: "Rate limit exceeded" } })
      end

      it "raises ModelThrottledError" do
        expect {
          collect_events(model, messages)
        }.to raise_error(Strands::Types::Exceptions::ModelThrottledError, /Rate limit exceeded/)
      end
    end

    context "with context window overflow" do
      before do
        stub_http_error(400, { error: { message: "context_length_exceeded", code: "context_length_exceeded" } })
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
