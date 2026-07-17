# frozen_string_literal: true

require "spec_helper"

RSpec.describe Strands::Tools::MCPClient do
  describe "#initialize" do
    it "defaults to stdio transport" do
      client = described_class.new(command: "python", args: ["-m", "server"])
      expect(client.transport).to eq(:stdio)
    end

    it "accepts http transport" do
      client = described_class.new(transport: :http, url: "http://localhost:8080/mcp")
      expect(client.transport).to eq(:http)
    end

    it "is not connected initially" do
      client = described_class.new(command: "python")
      expect(client.connected?).to be false
    end
  end

  describe "#connected?" do
    it "returns false before start" do
      client = described_class.new(command: "python")
      expect(client.connected?).to be false
    end
  end

  describe "stdio transport" do
    subject(:client) do
      described_class.new(
        transport: :stdio,
        command: "python",
        args: ["-m", "mcp_server"],
        timeout: 5
      )
    end

    let(:mock_stdin) { instance_double(IO, write: nil, flush: nil, close: nil) }
    let(:mock_stdout) { instance_double(IO, close: nil) }
    let(:child_in_read) { instance_double(IO, close: nil) }
    let(:child_out_write) { instance_double(IO, close: nil) }

    before do
      allow(IO).to receive(:pipe).and_return(
        [child_in_read, mock_stdin],
        [mock_stdout, child_out_write]
      )
      allow(client).to receive(:spawn).and_return(12345)
    end

    describe "#start" do
      let(:init_response) do
        {
          "jsonrpc" => "2.0",
          "id" => 1,
          "result" => {
            "protocolVersion" => "2024-11-05",
            "capabilities" => {},
            "serverInfo" => { "name" => "test-server", "version" => "1.0" }
          }
        }
      end

      before do
        stub_stdio_response(mock_stdout, init_response)
      end

      it "spawns the subprocess" do
        client.start
        expect(client).to have_received(:spawn)
      end

      it "sets connected to true after initialization" do
        client.start
        expect(client.connected?).to be true
      end

      it "sends initialize request" do
        expect(mock_stdin).to receive(:write) do |data|
          expect(data).to include("initialize")
          expect(data).to include("Content-Length:")
        end.at_least(:once)
        client.start
      end
    end

    describe "#list_tools" do
      let(:init_response) do
        {
          "jsonrpc" => "2.0",
          "id" => 1,
          "result" => {
            "protocolVersion" => "2024-11-05",
            "capabilities" => {}
          }
        }
      end

      let(:tools_response) do
        {
          "jsonrpc" => "2.0",
          "id" => 2,
          "result" => {
            "tools" => [
              {
                "name" => "search",
                "description" => "Search the web",
                "inputSchema" => {
                  "type" => "object",
                  "properties" => { "query" => { "type" => "string" } }
                }
              },
              {
                "name" => "calc",
                "description" => "Calculate",
                "inputSchema" => {
                  "type" => "object",
                  "properties" => { "expr" => { "type" => "string" } }
                }
              }
            ]
          }
        }
      end

      before do
        stub_stdio_responses(mock_stdout, [init_response, tools_response])
        client.start
      end

      it "returns parsed tool list" do
        tools = client.list_tools
        expect(tools.length).to eq(2)
        expect(tools.first["name"]).to eq("search")
        expect(tools.first["description"]).to eq("Search the web")
        expect(tools.first["input_schema"]).to eq({
          "type" => "object",
          "properties" => { "query" => { "type" => "string" } }
        })
      end
    end

    describe "#call_tool" do
      let(:init_response) do
        {
          "jsonrpc" => "2.0",
          "id" => 1,
          "result" => { "protocolVersion" => "2024-11-05", "capabilities" => {} }
        }
      end

      let(:tool_result_response) do
        {
          "jsonrpc" => "2.0",
          "id" => 2,
          "result" => {
            "content" => [{ "type" => "text", "text" => "42" }],
            "isError" => false
          }
        }
      end

      before do
        stub_stdio_responses(mock_stdout, [init_response, tool_result_response])
        client.start
      end

      it "sends tools/call request and returns result" do
        result = client.call_tool("calc", { expr: "6*7" })
        expect(result["content"]).to eq([{ "type" => "text", "text" => "42" }])
      end

      it "sends the tool name and arguments in the request" do
        expect(mock_stdin).to receive(:write) do |data|
          expect(data).to include("tools/call")
        end
        client.call_tool("calc", { expr: "6*7" })
      end
    end

    describe "#stop" do
      let(:init_response) do
        {
          "jsonrpc" => "2.0",
          "id" => 1,
          "result" => { "protocolVersion" => "2024-11-05", "capabilities" => {} }
        }
      end

      before do
        stub_stdio_response(mock_stdout, init_response)
        client.start
      end

      it "sends cancelled notification" do
        expect(mock_stdin).to receive(:write) do |data|
          expect(data).to include("notifications/cancelled")
        end
        allow(Process).to receive(:kill)
        allow(Process).to receive(:wait)
        client.stop
      end

      it "sets connected to false" do
        allow(Process).to receive(:kill)
        allow(Process).to receive(:wait)
        client.stop
        expect(client.connected?).to be false
      end

      it "kills the subprocess" do
        expect(Process).to receive(:kill).with("TERM", 12345)
        allow(Process).to receive(:wait)
        client.stop
      end
    end
  end

  describe "HTTP transport" do
    subject(:client) do
      described_class.new(
        transport: :http,
        url: "http://localhost:8080/mcp",
        headers: { "Authorization" => "Bearer test-token" }
      )
    end

    describe "#start" do
      let(:init_response_body) do
        JSON.generate({
          "jsonrpc" => "2.0",
          "id" => 1,
          "result" => {
            "protocolVersion" => "2024-11-05",
            "capabilities" => {},
            "serverInfo" => { "name" => "http-server", "version" => "1.0" }
          }
        })
      end

      before do
        stub_http_post(init_response_body)
      end

      it "sets connected to true" do
        client.start
        expect(client.connected?).to be true
      end

      it "sends initialize request over HTTP" do
        mock_request_class = class_double(Net::HTTP::Post).as_stubbed_const
        mock_request = instance_double(Net::HTTP::Post)
        allow(mock_request_class).to receive(:new).and_return(mock_request)
        allow(mock_request).to receive(:[]=)
        allow(mock_request).to receive(:body=)

        mock_response = instance_double(Net::HTTPResponse, body: init_response_body)
        mock_http = instance_double(Net::HTTP)
        allow(mock_http).to receive(:use_ssl=)
        allow(mock_http).to receive(:request).and_return(mock_response)
        allow(Net::HTTP).to receive(:new).and_return(mock_http)

        client.start
      end
    end

    describe "#list_tools" do
      let(:init_response_body) do
        JSON.generate({
          "jsonrpc" => "2.0",
          "id" => 1,
          "result" => { "protocolVersion" => "2024-11-05", "capabilities" => {} }
        })
      end

      let(:tools_response_body) do
        JSON.generate({
          "jsonrpc" => "2.0",
          "id" => 2,
          "result" => {
            "tools" => [
              {
                "name" => "web_search",
                "description" => "Search the web",
                "inputSchema" => { "type" => "object", "properties" => {} }
              }
            ]
          }
        })
      end

      before do
        stub_http_post_sequence([init_response_body, tools_response_body])
        client.start
      end

      it "sends tools/list over HTTP and returns tools" do
        tools = client.list_tools
        expect(tools.length).to eq(1)
        expect(tools.first["name"]).to eq("web_search")
      end
    end

    describe "#call_tool" do
      let(:init_response_body) do
        JSON.generate({
          "jsonrpc" => "2.0",
          "id" => 1,
          "result" => { "protocolVersion" => "2024-11-05", "capabilities" => {} }
        })
      end

      let(:call_response_body) do
        JSON.generate({
          "jsonrpc" => "2.0",
          "id" => 2,
          "result" => {
            "content" => [{ "type" => "text", "text" => "result data" }]
          }
        })
      end

      before do
        stub_http_post_sequence([init_response_body, call_response_body])
        client.start
      end

      it "sends tools/call over HTTP and returns result" do
        result = client.call_tool("web_search", { query: "ruby" })
        expect(result["content"]).to eq([{ "type" => "text", "text" => "result data" }])
      end
    end
  end

  describe "#to_definitions" do
    subject(:client) do
      described_class.new(transport: :stdio, command: "python", args: ["-m", "server"])
    end

    before do
      allow(client).to receive(:connected?).and_return(true)
      client.instance_variable_set(:@connected, true)
      allow(client).to receive(:list_tools).and_return([
        {
          "name" => "search",
          "description" => "Search the web",
          "input_schema" => { "type" => "object", "properties" => { "q" => { "type" => "string" } } }
        }
      ])
    end

    it "returns an array of Definition objects" do
      definitions = client.to_definitions
      expect(definitions.length).to eq(1)
      expect(definitions.first).to be_a(Strands::Tools::Definition)
    end

    it "sets the name from MCP tool" do
      definitions = client.to_definitions
      expect(definitions.first.name).to eq("search")
    end

    it "sets the description from MCP tool" do
      definitions = client.to_definitions
      expect(definitions.first.description).to eq("Search the web")
    end

    it "sets the input_schema from MCP tool" do
      definitions = client.to_definitions
      expect(definitions.first.input_schema).to include("type" => "object")
    end
  end

  describe "error cases" do
    subject(:client) do
      described_class.new(transport: :stdio, command: "python")
    end

    describe "#list_tools when not connected" do
      it "raises RuntimeError" do
        expect {
          client.list_tools
        }.to raise_error(RuntimeError, /not connected/)
      end
    end

    describe "#call_tool when not connected" do
      it "raises RuntimeError" do
        expect {
          client.call_tool("test", {})
        }.to raise_error(RuntimeError, /not connected/)
      end
    end

    describe "#start with initialization failure" do
      let(:mock_stdin) { instance_double(IO, write: nil, flush: nil, close: nil) }
      let(:mock_stdout) { instance_double(IO, close: nil) }
      let(:child_in_read) { instance_double(IO, close: nil) }
      let(:child_out_write) { instance_double(IO, close: nil) }

      let(:error_response) do
        {
          "jsonrpc" => "2.0",
          "id" => 1,
          "error" => { "code" => -32600, "message" => "Invalid protocol version" }
        }
      end

      before do
        allow(IO).to receive(:pipe).and_return(
          [child_in_read, mock_stdin],
          [mock_stdout, child_out_write]
        )
        allow(client).to receive(:spawn).and_return(99999)
        stub_stdio_response(mock_stdout, error_response)
      end

      it "raises RuntimeError with initialization failure message" do
        expect {
          client.start
        }.to raise_error(RuntimeError, /MCP initialization failed/)
      end
    end
  end

  # Helper methods

  def stub_stdio_response(mock_stdout, response)
    json = JSON.generate(response)
    framed = "Content-Length: #{json.bytesize}\r\n\r\n#{json}"
    lines = framed.split("\n").map { |l| "#{l}\n" }

    # Simulate header line, blank line, then body
    header_line = "Content-Length: #{json.bytesize}\r\n"
    blank_line = "\r\n"

    allow(mock_stdout).to receive(:gets).and_return(header_line, blank_line)
    allow(IO).to receive(:select).and_return([[mock_stdout]])
    allow(mock_stdout).to receive(:read_nonblock).and_return(json)
  end

  def stub_stdio_responses(mock_stdout, responses)
    headers = responses.map { |r| "Content-Length: #{JSON.generate(r).bytesize}\r\n" }
    blank = "\r\n"
    bodies = responses.map { |r| JSON.generate(r) }

    header_returns = headers.flat_map { |h| [h, blank] }
    allow(mock_stdout).to receive(:gets).and_return(*header_returns)
    allow(IO).to receive(:select).and_return([[mock_stdout]])
    allow(mock_stdout).to receive(:read_nonblock).and_return(*bodies)
  end

  def stub_http_post(response_body)
    mock_response = instance_double(Net::HTTPResponse, body: response_body)
    mock_http = instance_double(Net::HTTP)
    allow(mock_http).to receive(:use_ssl=)
    allow(mock_http).to receive(:request).and_return(mock_response)
    allow(Net::HTTP).to receive(:new).and_return(mock_http)
  end

  def stub_http_post_sequence(response_bodies)
    responses = response_bodies.map { |body| instance_double(Net::HTTPResponse, body: body) }
    mock_http = instance_double(Net::HTTP)
    allow(mock_http).to receive(:use_ssl=)
    allow(mock_http).to receive(:request).and_return(*responses)
    allow(Net::HTTP).to receive(:new).and_return(mock_http)
  end
end
