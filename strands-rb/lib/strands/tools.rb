# frozen_string_literal: true

module Strands
  # Tool system providing registration, execution, and DSL for defining tools.
  #
  # This module contains everything needed for tool definition, registration,
  # execution, and external tool integration via MCP.
  module Tools
    autoload :Definition, "strands/tools/definition"
    autoload :DSL, "strands/tools/dsl"
    autoload :Registry, "strands/tools/registry"
    autoload :Executor, "strands/tools/executor"
    autoload :ToolContext, "strands/tools/tool_context"
    autoload :MCPClient, "strands/tools/mcp_client"
    autoload :ToolProvider, "strands/tools/tool_provider"
  end
end
