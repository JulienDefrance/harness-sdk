# frozen_string_literal: true

module Strands
  module Tools
    # DSL methods for defining tools in a Ruby-idiomatic way.
    #
    # Provides the `Strands.tool` class method for defining tools inline
    # using blocks, lambdas, or method references.
    #
    # @example Define a tool with a block
    #   calculator = Strands.tool("calculator",
    #     description: "Evaluates a math expression",
    #     schema: {
    #       properties: { expression: { type: "string", description: "Math expression" } },
    #       required: ["expression"]
    #     }
    #   ) { |expression:| eval(expression).to_s }
    #
    # @example Define a tool with minimal schema
    #   greeter = Strands.tool("greeter", description: "Says hello") do |name: "World"|
    #     "Hello, #{name}!"
    #   end
    #
    module DSL
      # Defines a tool with the given name, description, schema, and implementation block.
      #
      # @param name [String] the unique tool name
      # @param description [String] human-readable description of the tool
      # @param schema [Hash] JSON Schema for input parameters (defaults to empty object schema)
      # @param callable [Proc, nil] an existing Proc/lambda to use (alternative to block)
      # @param block [Proc] the tool implementation (alternative to callable)
      # @return [Definition] the created tool definition
      # @raise [ArgumentError] if neither callable nor block is provided
      def self.define_tool(name, description:, schema: {}, callable: nil, &block)
        impl = callable || block
        raise ArgumentError, "a callable or block is required to define a tool" unless impl

        Definition.new(
          name: name,
          description: description,
          input_schema: schema,
          callable: impl
        )
      end
    end
  end
end

