# frozen_string_literal: true

module Strands
  module Tools
    # Executes tools given a ToolUse request and a Registry.
    #
    # The Executor is responsible for:
    # - Looking up tools in the registry
    # - Invoking the tool with proper context
    # - Wrapping the result in a ToolResult
    # - Handling errors gracefully (returning error status, not crashing)
    #
    # @example
    #   executor = Strands::Tools::Executor.new(registry)
    #   tool_use = Strands::Types::Tools::ToolUse.new(
    #     name: "calculator", tool_use_id: "123", input: { expression: "2+2" }
    #   )
    #   result = executor.execute(tool_use)
    #   result.status # => :success
    #
    class Executor
      # @return [Registry] the tool registry
      attr_reader :registry

      # Creates a new Executor.
      #
      # @param registry [Registry] the tool registry to look up tools
      def initialize(registry)
        @registry = registry
      end

      # Executes a tool based on a ToolUse request.
      #
      # @param tool_use [Strands::Types::Tools::ToolUse] the tool use request
      # @param agent [Object, nil] the agent executing the tool
      # @param invocation_state [Hash] additional state from the caller
      # @return [Strands::Types::Tools::ToolResult] the execution result
      def execute(tool_use, agent: nil, invocation_state: {})
        definition = registry.get(tool_use.name)

        unless definition
          return error_result(
            tool_use.tool_use_id,
            "Tool '#{tool_use.name}' not found in registry"
          )
        end

        context = ToolContext.new(
          tool_use: tool_use,
          agent: agent,
          invocation_state: invocation_state
        )

        invoke_tool(definition, tool_use, context)
      rescue StandardError => e
        error_result(tool_use.tool_use_id, "#{e.class}: #{e.message}")
      end

      private

      # Invokes a tool definition and wraps the result.
      #
      # @param definition [Definition] the tool definition
      # @param tool_use [ToolUse] the tool use request
      # @param context [ToolContext] the execution context
      # @return [Strands::Types::Tools::ToolResult]
      def invoke_tool(definition, tool_use, context)
        input = normalize_input(tool_use.input)
        result = definition.call(input, context: context)
        success_result(tool_use.tool_use_id, result)
      rescue StandardError => e
        error_result(tool_use.tool_use_id, "#{e.class}: #{e.message}")
      end

      # Normalizes tool input to a Hash.
      #
      # @param input [Object] the raw input
      # @return [Hash]
      def normalize_input(input)
        case input
        when Hash
          input
        when nil
          {}
        else
          { value: input }
        end
      end

      # Creates a success ToolResult.
      #
      # @param tool_use_id [String] the tool use ID
      # @param result [Object] the tool's return value
      # @return [Strands::Types::Tools::ToolResult]
      def success_result(tool_use_id, result)
        content = format_content(result)

        Types::Tools::ToolResult.new(
          tool_use_id: tool_use_id,
          content: content,
          status: :success
        )
      end

      # Creates an error ToolResult.
      #
      # @param tool_use_id [String] the tool use ID
      # @param message [String] the error message
      # @return [Strands::Types::Tools::ToolResult]
      def error_result(tool_use_id, message)
        content = [
          Types::Tools::ToolResultContent.new(text: "Error: #{message}")
        ]

        Types::Tools::ToolResult.new(
          tool_use_id: tool_use_id,
          content: content,
          status: :error
        )
      end

      # Formats a tool return value into ToolResultContent array.
      #
      # @param result [Object] the raw result
      # @return [Array<Strands::Types::Tools::ToolResultContent>]
      def format_content(result)
        case result
        when Types::Tools::ToolResult
          # If the tool already returned a ToolResult, use its content
          result.content
        when Array
          # If it's an array of ToolResultContent, use directly
          if result.all? { |r| r.is_a?(Types::Tools::ToolResultContent) }
            result
          else
            [Types::Tools::ToolResultContent.new(text: result.inspect)]
          end
        when Hash
          # JSON-serializable hash
          [Types::Tools::ToolResultContent.new(json: result)]
        when String
          [Types::Tools::ToolResultContent.new(text: result)]
        when nil
          [Types::Tools::ToolResultContent.new(text: "")]
        else
          [Types::Tools::ToolResultContent.new(text: result.to_s)]
        end
      end
    end
  end
end
