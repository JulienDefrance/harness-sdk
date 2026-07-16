# frozen_string_literal: true

module Strands
  module Tools
    # Interface for tool providers that supply tools dynamically.
    #
    # A ToolProvider is any object that can produce a set of tool Definitions
    # for use by an agent. This allows external systems (like MCP servers or
    # plugin registries) to integrate with the tool system.
    #
    # @example Implementing a ToolProvider
    #   class MyProvider
    #     include Strands::Tools::ToolProvider
    #
    #     def get_tools
    #       [
    #         Strands::Tools::Definition.new(
    #           name: "my_tool",
    #           description: "Does something",
    #           input_schema: {},
    #           callable: -> { "result" }
    #         )
    #       ]
    #     end
    #   end
    #
    module ToolProvider
      # Returns the tools provided by this provider.
      #
      # @return [Array<Definition>] the tool definitions
      def get_tools
        raise NotImplementedError, "#{self.class}#get_tools must be implemented"
      end
    end
  end
end
