# frozen_string_literal: true

module Strands
  module Tools
    # Central registry for all tools available to an agent.
    #
    # Manages tool registration, lookup, and specification generation.
    # Supports registering Definition objects, Proc/lambda callables, or
    # objects responding to `#tool_spec` and `#call`.
    #
    # @example Basic usage
    #   registry = Strands::Tools::Registry.new
    #   registry.register(my_tool_definition)
    #   registry.get("my_tool")
    #   registry.tool_specs # => [ToolSpec, ...]
    #
    class Registry
      # @return [Hash{String => Definition}] the internal tool storage
      attr_reader :tools

      def initialize
        @tools = {}
      end

      # Registers a tool definition in the registry.
      #
      # @param tool [Definition, Hash, Object] the tool to register.
      #   If a Hash, must contain :name, :description, :input_schema, :callable keys.
      #   If an object, must respond to #name and #call.
      # @raise [ArgumentError] if a tool with the same name is already registered
      # @raise [ArgumentError] if the tool format is unrecognized
      # @return [Definition] the registered definition
      def register(tool)
        definition = coerce_to_definition(tool)

        if @tools.key?(definition.name)
          raise ArgumentError, "Tool '#{definition.name}' is already registered"
        end

        # Check for normalized name conflicts (- vs _)
        normalized = definition.name.tr("-", "_")
        conflict = @tools.keys.find { |k| k.tr("-", "_") == normalized && k != definition.name }
        if conflict
          raise ArgumentError,
                "Tool '#{definition.name}' conflicts with '#{conflict}' (differ only by - vs _)"
        end

        @tools[definition.name] = definition
      end

      # Retrieves a tool by name.
      #
      # @param name [String] the tool name
      # @return [Definition, nil] the tool definition, or nil if not found
      def get(name)
        @tools[name.to_s]
      end

      # Retrieves a tool by name, raising if not found.
      #
      # @param name [String] the tool name
      # @return [Definition] the tool definition
      # @raise [KeyError] if tool is not found
      def fetch(name)
        @tools.fetch(name.to_s) do
          raise KeyError, "Tool '#{name}' not found in registry"
        end
      end

      # Lists all registered tool names.
      #
      # @return [Array<String>]
      def list
        @tools.keys
      end

      # Returns the number of registered tools.
      #
      # @return [Integer]
      def size
        @tools.size
      end

      # Checks if a tool is registered.
      #
      # @param name [String] the tool name
      # @return [Boolean]
      def registered?(name)
        @tools.key?(name.to_s)
      end

      # Returns tool specifications for all registered tools.
      # This is the format expected by model APIs.
      #
      # @return [Array<Strands::Types::Tools::ToolSpec>]
      def tool_specs
        @tools.values.map(&:tool_spec)
      end

      # Removes a tool from the registry.
      #
      # @param name [String] the tool name to remove
      # @return [Definition, nil] the removed definition, or nil
      def unregister(name)
        @tools.delete(name.to_s)
      end

      # Processes an array of tools in various formats and registers them.
      #
      # Supported formats:
      # - Definition instances
      # - Hashes with :name, :description, :input_schema, :callable
      # - Objects responding to #name, #tool_spec, and #call
      # - Arrays (processed recursively)
      #
      # @param tools_array [Array] tools in various formats
      # @return [Array<String>] names of tools that were registered
      def process_tools(tools_array)
        registered_names = []

        Array(tools_array).each do |tool|
          if tool.is_a?(Array)
            registered_names.concat(process_tools(tool))
          else
            definition = register(tool)
            registered_names << definition.name
          end
        end

        registered_names
      end

      # Removes all tools from the registry.
      #
      # @return [void]
      def clear
        @tools.clear
      end

      private

      # Coerces various tool formats into a Definition.
      #
      # @param tool [Object] the tool to coerce
      # @return [Definition]
      # @raise [ArgumentError] if format is unrecognized
      def coerce_to_definition(tool)
        case tool
        when Definition
          tool
        when Hash
          Definition.new(
            name: tool[:name] || tool["name"],
            description: tool[:description] || tool["description"],
            input_schema: tool[:input_schema] || tool["input_schema"] || {},
            callable: tool[:callable] || tool["callable"]
          )
        else
          if tool.respond_to?(:name) && tool.respond_to?(:call)
            Definition.new(
              name: tool.name,
              description: tool.respond_to?(:description) ? tool.description : tool.name,
              input_schema: tool.respond_to?(:input_schema) ? tool.input_schema : {},
              callable: tool.method(:call)
            )
          else
            raise ArgumentError, "Unrecognized tool format: #{tool.class}. " \
                                 "Expected Definition, Hash, or object responding to #name and #call"
          end
        end
      end
    end
  end
end
