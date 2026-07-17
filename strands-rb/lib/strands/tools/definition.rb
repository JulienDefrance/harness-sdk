# frozen_string_literal: true

module Strands
  module Tools
    # Represents a tool definition wrapping a callable with metadata.
    #
    # A Definition encapsulates everything needed to describe and invoke a tool:
    # the tool's name, description, input schema, and the callable that implements it.
    #
    # @example Creating a definition with explicit schema
    #   definition = Strands::Tools::Definition.new(
    #     name: "calculator",
    #     description: "Performs arithmetic",
    #     input_schema: {
    #       type: "object",
    #       properties: {
    #         expression: { type: "string", description: "Math expression" }
    #       },
    #       required: ["expression"]
    #     },
    #     callable: ->(expression:) { eval(expression).to_s }
    #   )
    #
    class Definition
      # @return [String] the unique tool name
      attr_reader :name

      # @return [String] human-readable description
      attr_reader :description

      # @return [Hash] JSON Schema for the tool's input parameters
      attr_reader :input_schema

      # @return [Proc, Method] the callable implementing the tool
      attr_reader :callable

      # Creates a new tool definition.
      #
      # @param name [String] the unique tool name
      # @param description [String] human-readable description
      # @param input_schema [Hash] JSON Schema defining expected input parameters
      # @param callable [Proc, Method] the callable implementing the tool
      def initialize(name:, description:, input_schema:, callable:)
        @name = name.to_s
        @description = description.to_s
        @input_schema = normalize_schema(input_schema)
        @callable = callable

        validate!
      end

      # Creates a Definition from a block with explicit metadata.
      #
      # @param name [String] the tool name
      # @param description [String] the tool description
      # @param schema [Hash] the input schema
      # @param block [Proc] the tool implementation
      # @return [Definition] a new Definition instance
      def self.from_block(name:, description:, schema: {}, &block)
        raise ArgumentError, "a block is required" unless block_given?

        new(
          name: name,
          description: description,
          input_schema: schema,
          callable: block
        )
      end

      # Invokes the tool with the given input parameters.
      #
      # @param input [Hash] the input parameters (string or symbol keys accepted)
      # @param context [ToolContext, nil] optional execution context
      # @return [Object] the tool's return value
      def call(input = nil, **opts)
        input = input || {}
        context = opts[:context]
        args = build_arguments(input, context)
        callable.call(**args)
      end

      # Returns the tool specification in the format expected by model APIs.
      #
      # @return [Strands::Types::Tools::ToolSpec]
      def tool_spec
        Types::Tools::ToolSpec.new(
          name: name,
          description: description,
          input_schema: input_schema
        )
      end

      # Returns a hash representation of the tool spec for API serialization.
      #
      # @return [Hash]
      def to_h
        {
          name: name,
          description: description,
          input_schema: input_schema
        }
      end

      private

      # Validates the definition has the required fields.
      def validate!
        raise ArgumentError, "name cannot be empty" if @name.empty?
        raise ArgumentError, "description cannot be empty" if @description.empty?
        raise ArgumentError, "callable must respond to #call" unless @callable.respond_to?(:call)
      end

      # Normalizes the input schema to ensure it has required fields.
      #
      # @param schema [Hash] the raw schema
      # @return [Hash] normalized schema
      def normalize_schema(schema)
        schema = schema.transform_keys(&:to_s) if schema.is_a?(Hash)
        result = {
          "type" => "object",
          "properties" => {},
          "required" => []
        }
        return result unless schema.is_a?(Hash)

        result["type"] = schema["type"] || "object"
        result["properties"] = normalize_properties(schema["properties"] || {})
        result["required"] = (schema["required"] || []).map(&:to_s)
        result
      end

      # Normalizes property definitions within the schema.
      #
      # @param properties [Hash] raw properties
      # @return [Hash] normalized properties
      def normalize_properties(properties)
        properties.each_with_object({}) do |(key, value), normalized|
          key = key.to_s
          if value.is_a?(Hash)
            prop = value.transform_keys(&:to_s)
            prop["type"] ||= "string"
            prop["description"] ||= "Parameter #{key}"
            normalized[key] = prop
          else
            normalized[key] = { "type" => "string", "description" => "Parameter #{key}" }
          end
        end
      end

      # Builds the argument hash for calling the tool.
      #
      # @param input [Hash] the raw input
      # @param context [ToolContext, nil] optional context
      # @return [Hash] symbolized arguments
      def build_arguments(input, context)
        args = {}
        input.each { |k, v| args[k.to_sym] = v }

        # Inject context if the callable accepts a tool_context parameter
        if context && accepts_parameter?(:tool_context)
          args[:tool_context] = context
        end

        args
      end

      # Checks if the callable accepts a given parameter name.
      #
      # @param name [Symbol] the parameter name
      # @return [Boolean]
      def accepts_parameter?(name)
        return false unless callable.respond_to?(:parameters)

        callable.parameters.any? { |_type, param_name| param_name == name }
      end
    end
  end
end
