# frozen_string_literal: true

require "json"

module Strands
  module Tools
    # Model Context Protocol (MCP) client for connecting to MCP servers.
    #
    # Provides MCP protocol support - connecting to MCP servers via stdio (subprocess)
    # or HTTP (streamable HTTP/SSE), listing tools, and calling tools using JSON-RPC 2.0.
    #
    # @example Using stdio transport
    #   client = Strands::Tools::MCPClient.new(
    #     transport: :stdio,
    #     command: "python",
    #     args: ["-m", "my_mcp_server"]
    #   )
    #   client.start
    #   tools = client.list_tools
    #   result = client.call_tool("my_tool", { param: "value" })
    #   client.stop
    #
    # @example Using HTTP transport
    #   client = Strands::Tools::MCPClient.new(
    #     transport: :http,
    #     url: "http://localhost:8080/mcp"
    #   )
    #   client.start
    #   tools = client.list_tools
    #   client.stop
    #
    class MCPClient
      # JSON-RPC version used by MCP protocol
      JSONRPC_VERSION = "2.0"

      # MCP protocol version
      MCP_PROTOCOL_VERSION = "2024-11-05"

      # @return [Symbol] the transport type (:stdio or :http)
      attr_reader :transport

      # @return [Boolean] whether the client is connected
      attr_reader :connected

      # Creates a new MCPClient.
      #
      # @param transport [Symbol] the transport type (:stdio or :http)
      # @param command [String, nil] the command to spawn for stdio transport
      # @param args [Array<String>] arguments for the stdio command
      # @param env [Hash] environment variables for the subprocess
      # @param url [String, nil] the HTTP endpoint URL for HTTP transport
      # @param headers [Hash] additional HTTP headers
      # @param timeout [Numeric] read timeout in seconds for stdio responses (default: 60)
      def initialize(transport: :stdio, command: nil, args: [], env: {}, url: nil, headers: {}, timeout: 60)
        @transport = transport
        @command = command
        @args = args
        @env = env
        @url = url
        @headers = headers
        @timeout = timeout
        @connected = false
        @request_id = 0
        @io_in = nil
        @io_out = nil
        @process = nil
      end

      # Starts the MCP client connection.
      #
      # For stdio transport, spawns the subprocess and performs initialization.
      # For HTTP transport, establishes the HTTP connection.
      #
      # @return [void]
      # @raise [MCPConnectionError] if connection fails
      def start
        case @transport
        when :stdio
          start_stdio
        when :http
          start_http
        else
          raise ArgumentError, "Unknown transport: #{@transport}"
        end

        initialize_connection
        @connected = true
      end

      # Stops the MCP client connection.
      #
      # @return [void]
      def stop
        return unless @connected

        send_notification("notifications/cancelled", {})
        @connected = false

        case @transport
        when :stdio
          stop_stdio
        when :http
          stop_http
        end
      end

      # Lists available tools from the MCP server.
      #
      # @return [Array<Hash>] array of tool descriptions with name, description, and input_schema
      def list_tools
        ensure_connected!
        response = send_request("tools/list", {})
        tools = response.dig("result", "tools") || []
        tools.map do |tool|
          {
            "name" => tool["name"],
            "description" => tool["description"] || "",
            "input_schema" => tool["inputSchema"] || {}
          }
        end
      end

      # Calls a tool on the MCP server.
      #
      # @param name [String] the tool name
      # @param arguments [Hash] the tool input arguments
      # @return [Hash] the tool result with "content" and optional "isError" keys
      def call_tool(name, arguments = {})
        ensure_connected!
        response = send_request("tools/call", { name: name, arguments: arguments })
        response["result"] || {}
      end

      # Converts MCP tools to Strands tool Definitions for registry integration.
      #
      # @return [Array<Definition>] array of Definition objects wrapping MCP tool calls
      def to_definitions
        list_tools.map do |tool|
          mcp_client = self
          tool_name = tool["name"]

          Definition.new(
            name: tool_name,
            description: tool["description"],
            input_schema: tool["input_schema"],
            callable: lambda { |**kwargs|
              result = mcp_client.call_tool(tool_name, kwargs)
              if result["isError"]
                raise StandardError, extract_error_text(result)
              end

              extract_content_text(result)
            }
          )
        end
      end

      # Whether the client is currently connected.
      #
      # @return [Boolean]
      def connected?
        @connected
      end

      private

      # Ensures the client is connected before operations.
      def ensure_connected!
        raise RuntimeError, "MCPClient is not connected. Call #start first." unless @connected
      end

      # Starts stdio transport by spawning a subprocess.
      def start_stdio
        raise ArgumentError, "command is required for stdio transport" unless @command

        @io_in, @io_out, @process = spawn_process
      end

      # Starts HTTP transport.
      def start_http
        raise ArgumentError, "url is required for HTTP transport" unless @url

        # HTTP connections are stateless; we just validate config here
        require "net/http"
        require "uri"
        @uri = URI.parse(@url)
      end

      # Stops the stdio subprocess.
      def stop_stdio
        return unless @process

        @io_in&.close
        @io_out&.close
        Process.kill("TERM", @process) rescue nil # rubocop:disable Style/RescueModifier
        Process.wait(@process) rescue nil # rubocop:disable Style/RescueModifier
        @process = nil
      end

      # Stops the HTTP connection.
      def stop_http
        # HTTP is stateless; nothing to close
      end

      # Spawns a subprocess for stdio transport.
      #
      # @return [Array(IO, IO, Integer)] stdin, stdout, pid
      def spawn_process
        cmd = [@command] + @args
        child_in, parent_in = IO.pipe
        parent_out, child_out = IO.pipe

        pid = spawn(@env, *cmd, in: child_in, out: child_out, err: :close)
        child_in.close
        child_out.close

        [parent_in, parent_out, pid]
      end

      # Performs the MCP initialize handshake.
      def initialize_connection
        case @transport
        when :stdio
          response = send_request("initialize", {
            protocolVersion: MCP_PROTOCOL_VERSION,
            capabilities: {},
            clientInfo: { name: "strands-rb", version: Strands::VERSION }
          })

          if response["error"]
            raise RuntimeError, "MCP initialization failed: #{response['error']['message']}"
          end

          send_notification("notifications/initialized", {})
        when :http
          # For HTTP, initialization may be handled per-request or via session
          response = send_request("initialize", {
            protocolVersion: MCP_PROTOCOL_VERSION,
            capabilities: {},
            clientInfo: { name: "strands-rb", version: Strands::VERSION }
          })

          if response["error"]
            raise RuntimeError, "MCP initialization failed: #{response['error']['message']}"
          end
        end
      end

      # Sends a JSON-RPC request and waits for a response.
      #
      # @param method [String] the JSON-RPC method
      # @param params [Hash] the parameters
      # @return [Hash] the parsed JSON-RPC response
      def send_request(method, params)
        @request_id += 1
        message = {
          jsonrpc: JSONRPC_VERSION,
          id: @request_id,
          method: method,
          params: params
        }

        case @transport
        when :stdio
          send_stdio_message(message)
          read_stdio_response
        when :http
          send_http_message(message)
        end
      end

      # Sends a JSON-RPC notification (no response expected).
      #
      # @param method [String] the JSON-RPC method
      # @param params [Hash] the parameters
      def send_notification(method, params)
        message = {
          jsonrpc: JSONRPC_VERSION,
          method: method,
          params: params
        }

        case @transport
        when :stdio
          send_stdio_message(message)
        when :http
          send_http_notification(message)
        end
      end

      # Sends a message over stdio.
      def send_stdio_message(message)
        json = JSON.generate(message)
        @io_in.write("Content-Length: #{json.bytesize}\r\n\r\n#{json}")
        @io_in.flush
      end

      # Reads a response from stdio with a timeout to prevent indefinite blocking.
      #
      # Uses IO.select with a deadline to ensure the calling thread is not blocked
      # forever if the MCP subprocess hangs or becomes unresponsive.
      #
      # @return [Hash] parsed JSON response
      # @raise [RuntimeError] if the read times out
      def read_stdio_response
        deadline = Time.now + @timeout

        # Read headers
        headers = ""
        loop do
          remaining = deadline - Time.now
          if remaining <= 0
            raise RuntimeError, "MCP stdio read timed out after #{@timeout}s waiting for headers"
          end

          ready = IO.select([@io_out], nil, nil, remaining)
          unless ready
            raise RuntimeError, "MCP stdio read timed out after #{@timeout}s waiting for headers"
          end

          line = @io_out.gets
          break if line.nil? || line.strip.empty?

          headers += line
        end

        # Parse content length
        content_length = headers[/Content-Length:\s*(\d+)/i, 1]&.to_i
        return {} unless content_length&.positive?

        # Read body with timeout
        body = +""
        while body.bytesize < content_length
          remaining = deadline - Time.now
          if remaining <= 0
            raise RuntimeError, "MCP stdio read timed out after #{@timeout}s waiting for body"
          end

          ready = IO.select([@io_out], nil, nil, remaining)
          unless ready
            raise RuntimeError, "MCP stdio read timed out after #{@timeout}s waiting for body"
          end

          chunk = @io_out.read_nonblock(content_length - body.bytesize)
          body << chunk
        end

        JSON.parse(body)
      rescue IO::WaitReadable
        # Retry if read_nonblock raises WaitReadable (should be handled by IO.select above)
        retry
      end

      # Sends a message over HTTP.
      #
      # @return [Hash] parsed JSON response
      def send_http_message(message)
        http = Net::HTTP.new(@uri.host, @uri.port)
        http.use_ssl = (@uri.scheme == "https")

        request = Net::HTTP::Post.new(@uri.request_uri)
        request["Content-Type"] = "application/json"
        @headers.each { |k, v| request[k.to_s] = v.to_s }
        request.body = JSON.generate(message)

        response = http.request(request)
        JSON.parse(response.body)
      end

      # Sends a notification over HTTP (fire and forget).
      def send_http_notification(message)
        send_http_message(message)
      rescue StandardError
        # Notifications don't require responses
      end

      # Extracts error text from an MCP result.
      #
      # @param result [Hash] the tool result
      # @return [String]
      def extract_error_text(result)
        content = result["content"] || []
        texts = content.filter_map { |c| c["text"] if c["type"] == "text" }
        texts.join("\n").then { |t| t.empty? ? "Unknown MCP error" : t }
      end

      # Extracts content text from an MCP result.
      #
      # @param result [Hash] the tool result
      # @return [String]
      def extract_content_text(result)
        content = result["content"] || []
        texts = content.filter_map { |c| c["text"] if c["type"] == "text" }
        texts.join("\n")
      end
    end
  end
end
