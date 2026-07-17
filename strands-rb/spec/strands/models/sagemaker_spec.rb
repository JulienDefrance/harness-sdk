# frozen_string_literal: true

require "spec_helper"

RSpec.describe Strands::Models::SageMaker do
  # Stub AWS classes
  before do
    stub_const("Aws::SageMakerRuntime::Client", Class.new)
  end

  let(:mock_client) { instance_double("Aws::SageMakerRuntime::Client") }

  subject(:model) do
    m = described_class.new(endpoint_name: "my-endpoint", region_name: "us-west-2", model_id: "llama3")
    # Inject mock client directly to bypass require "aws-sdk-sagemakerruntime"
    m.instance_variable_set(:@client, mock_client)
    m
  end

  describe "#initialize" do
    it "stores the endpoint_name in config" do
      expect(model.config[:endpoint_name]).to eq("my-endpoint")
    end

    it "stores the region_name in config" do
      expect(model.config[:region_name]).to eq("us-west-2")
    end

    it "stores the model_id in config" do
      expect(model.config[:model_id]).to eq("llama3")
    end
  end

  describe "#update_config" do
    it "merges new options into config" do
      model.update_config(endpoint_name: "new-endpoint")
      expect(model.config[:endpoint_name]).to eq("new-endpoint")
    end
  end

  describe "#get_config" do
    it "returns a copy of the config" do
      config = model.get_config
      config[:endpoint_name] = "modified"
      expect(model.config[:endpoint_name]).to eq("my-endpoint")
    end
  end

  describe "#inspect" do
    it "includes endpoint_name and model_id" do
      expect(model.inspect).to include("my-endpoint")
      expect(model.inspect).to include("llama3")
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

    it "formats system prompt" do
      request = model.format_request(messages, system_prompt: "Be helpful")
      expect(request[:messages].first[:role]).to eq("system")
      expect(request[:messages].first[:content]).to eq("Be helpful")
    end

    it "includes max_tokens from params" do
      m = described_class.new(endpoint_name: "ep", max_tokens: 512)
      request = m.format_request(messages)
      expect(request[:max_tokens]).to eq(512)
    end
  end

  describe "#stream" do
    let(:messages) { [{ role: :user, content: [{ text: "Hello" }] }] }

    context "with a successful text response" do
      before do
        sse_data = "data: #{JSON.generate({ choices: [{ delta: { content: "Hi" }, index: 0 }] })}\n\ndata: #{JSON.generate({ choices: [{ delta: {}, finish_reason: "stop", index: 0 }] })}\n\ndata: [DONE]\n\n"

        allow(mock_client).to receive(:invoke_endpoint_with_response_stream) do |**params, &block|
          # Simulate the event stream handler
          event_stream = double("EventStream")
          payload_handler = nil

          allow(event_stream).to receive(:on_payload_part_event) do |&handler|
            payload_handler = handler
          end

          block.call(event_stream)

          # Now trigger the event
          event = double("PayloadPartEvent", bytes: sse_data)
          payload_handler.call(event)
        end
      end

      it "yields message_start event" do
        events = collect_events(model, messages)
        expect(events.first.event_type).to eq(:message_start)
      end

      it "yields content_block_delta with text" do
        events = collect_events(model, messages)
        deltas = events.select { |e| e.event_type == :content_block_delta }
        texts = deltas.map { |e| e.content_block_delta.delta.text }.compact
        expect(texts).to eq(["Hi"])
      end

      it "yields message_stop with end_turn" do
        events = collect_events(model, messages)
        msg_stop = events.find { |e| e.event_type == :message_stop }
        expect(msg_stop.message_stop.stop_reason).to eq(:end_turn)
      end
    end

    context "with tool calls in response" do
      before do
        sse_data = [
          "data: #{JSON.generate({ choices: [{ delta: { tool_calls: [{ index: 0, id: "call_sm1", function: { name: "lookup", arguments: '{"id":1}' } }] }, index: 0 }] })}\n\n",
          "data: #{JSON.generate({ choices: [{ delta: {}, finish_reason: "tool_calls", index: 0 }] })}\n\n",
          "data: [DONE]\n\n"
        ].join

        allow(mock_client).to receive(:invoke_endpoint_with_response_stream) do |**params, &block|
          event_stream = double("EventStream")
          payload_handler = nil

          allow(event_stream).to receive(:on_payload_part_event) do |&handler|
            payload_handler = handler
          end

          block.call(event_stream)

          event = double("PayloadPartEvent", bytes: sse_data)
          payload_handler.call(event)
        end
      end

      it "yields tool use blocks" do
        events = collect_events(model, messages)
        starts = events.select { |e| e.event_type == :content_block_start }
        tool_starts = starts.select { |e| e.content_block_start.start&.tool_use }
        expect(tool_starts.length).to eq(1)
        expect(tool_starts.first.content_block_start.start.tool_use.name).to eq("lookup")
      end

      it "yields message_stop with tool_use reason" do
        events = collect_events(model, messages)
        msg_stop = events.find { |e| e.event_type == :message_stop }
        expect(msg_stop.message_stop.stop_reason).to eq(:tool_use)
      end
    end
  end

  def collect_events(model, messages)
    events = []
    model.stream(messages) { |e| events << e }
    events
  end
end
