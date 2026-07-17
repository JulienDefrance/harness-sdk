# frozen_string_literal: true

module Strands
  module Types
    # Tool-related type definitions for the SDK.
    #
    # These types define tool specifications, tool use requests, and tool results.
    # Modeled after the Bedrock API.
    module Tools
      # Specification for a tool that can be used by an agent.
      #
      # @attr name [String] the unique name of the tool
      # @attr description [String] human-readable description
      # @attr input_schema [Hash] JSON Schema defining expected input parameters
      # @attr output_schema [Hash, nil] optional JSON Schema for expected output
      ToolSpec = Struct.new(:name, :description, :input_schema, :output_schema, keyword_init: true) do
        def initialize(name:, description:, input_schema:, output_schema: nil)
          super(name: name, description: description, input_schema: input_schema, output_schema: output_schema)
        end
      end

      # A tool that can be provided to a model.
      #
      # @attr tool_spec [ToolSpec] the specification of the tool
      Tool = Struct.new(:tool_spec, keyword_init: true)

      # A request from the model to use a specific tool.
      #
      # @attr name [String] the name of the tool to invoke
      # @attr tool_use_id [String] unique identifier for this tool use request
      # @attr input [Object] the input parameters for the tool
      # @attr reasoning_signature [String, nil] token tying reasoning to this tool call
      ToolUse = Struct.new(:name, :tool_use_id, :input, :reasoning_signature, keyword_init: true) do
        def initialize(name:, tool_use_id:, input:, reasoning_signature: nil)
          super(name: name, tool_use_id: tool_use_id, input: input, reasoning_signature: reasoning_signature)
        end
      end

      # Content returned by a tool execution.
      #
      # @attr text [String, nil] text content
      # @attr json [Object, nil] JSON-serializable data
      # @attr image [Media::ImageContent, nil] image content
      # @attr document [Media::DocumentContent, nil] document content
      ToolResultContent = Struct.new(:text, :json, :image, :document, keyword_init: true)

      # Valid tool result statuses
      TOOL_RESULT_STATUSES = %i[success error].freeze

      # Result of a tool execution.
      #
      # @attr tool_use_id [String] the ID of the tool use request
      # @attr content [Array<ToolResultContent>] list of result content
      # @attr status [Symbol] the status (:success or :error)
      ToolResult = Struct.new(:tool_use_id, :content, :status, keyword_init: true) do
        def initialize(tool_use_id:, content:, status:)
          unless TOOL_RESULT_STATUSES.include?(status)
            raise ArgumentError, "status must be one of: #{TOOL_RESULT_STATUSES.join(', ')}"
          end

          super(tool_use_id: tool_use_id, content: content, status: status)
        end
      end

      # Context object containing framework-provided data for tool execution.
      #
      # @attr tool_use [ToolUse] the tool use request
      # @attr agent [Object] the Agent instance executing this tool
      # @attr invocation_state [Hash] caller-provided kwargs passed to the agent
      ToolContext = Struct.new(:tool_use, :agent, :invocation_state, keyword_init: true) do
        def initialize(tool_use:, agent:, invocation_state: {})
          super(tool_use: tool_use, agent: agent, invocation_state: invocation_state)
        end
      end

      # Configuration for automatic tool selection.
      ToolChoiceAuto = Struct.new(keyword_init: true)

      # Configuration indicating the model must request at least one tool.
      ToolChoiceAny = Struct.new(keyword_init: true)

      # Configuration for forcing the use of a specific tool.
      #
      # @attr name [String] the tool name the model must use
      ToolChoiceTool = Struct.new(:name, keyword_init: true)

      # Configuration for tools in a model request.
      #
      # @attr tools [Array<Tool>] list of tools available to the model
      # @attr tool_choice [ToolChoiceAuto, ToolChoiceAny, ToolChoiceTool] how the model should choose tools
      ToolConfig = Struct.new(:tools, :tool_choice, keyword_init: true)
    end
  end
end
