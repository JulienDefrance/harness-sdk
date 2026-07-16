# frozen_string_literal: true

module Strands
  module Tools
    # Context object provided to tools at execution time.
    #
    # ToolContext gives tools access to the current tool use request, the agent
    # executing the tool, and any invocation-level state passed by the caller.
    #
    # @example Accessing context in a tool
    #   Strands.tool("my_tool", description: "Example") do |tool_context:|
    #     agent = tool_context.agent
    #     tool_use = tool_context.tool_use
    #     # ...
    #   end
    #
    class ToolContext
      # @return [Strands::Types::Tools::ToolUse] the tool use request
      attr_reader :tool_use

      # @return [Object, nil] the Agent instance executing this tool
      attr_reader :agent

      # @return [Hash] caller-provided state passed to the agent
      attr_reader :invocation_state

      # Creates a new ToolContext.
      #
      # @param tool_use [Strands::Types::Tools::ToolUse] the tool use request
      # @param agent [Object, nil] the Agent instance
      # @param invocation_state [Hash] additional state from the caller
      def initialize(tool_use:, agent: nil, invocation_state: {})
        @tool_use = tool_use
        @agent = agent
        @invocation_state = invocation_state
      end

      # Returns the tool use ID from the current request.
      #
      # @return [String]
      def tool_use_id
        tool_use&.tool_use_id
      end

      # Returns the tool name from the current request.
      #
      # @return [String]
      def tool_name
        tool_use&.name
      end

      # Returns the input parameters from the current request.
      #
      # @return [Object]
      def input
        tool_use&.input
      end
    end
  end
end
