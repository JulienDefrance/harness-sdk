# frozen_string_literal: true

require_relative "strands/version"

# Strands - A framework for building, deploying, and managing AI agents.
#
# This is the main entry point for the Strands Ruby SDK.
# It provides a composable framework for building AI agents with support
# for multiple model providers, tool execution, hooks, interventions,
# and session management.
#
# @example Basic usage
#   agent = Strands::Agent.new(
#     model: Strands::Models::Bedrock.new(model_id: "anthropic.claude-3-5-sonnet"),
#     tools: [calculator]
#   )
#   result = agent.call("What is 2 + 2?")
#
module Strands
  class Error < StandardError; end

  # Autoload submodules for lazy loading
  autoload :Agent, "strands/agent"
  autoload :Models, "strands/models"
  autoload :Tools, "strands/tools"
  autoload :EventLoop, "strands/event_loop"
  autoload :Types, "strands/types"
  autoload :Hooks, "strands/hooks"
  autoload :Interventions, "strands/interventions"
  autoload :Plugins, "strands/plugins"
  autoload :Handlers, "strands/handlers"
  autoload :Memory, "strands/memory"
  autoload :Storage, "strands/storage"
  autoload :Session, "strands/session"
  autoload :Telemetry, "strands/telemetry"

  class << self
    # Defines a tool using the DSL.
    #
    # This is the primary entry point for defining tools in a Ruby-idiomatic way.
    # It creates a Tools::Definition that can be registered with a Registry or
    # passed directly to an Agent.
    #
    # @param name [String] the unique tool name
    # @param description [String] human-readable description
    # @param schema [Hash] JSON Schema for input parameters
    # @param callable [Proc, nil] an existing callable (alternative to block)
    # @param block [Proc] the tool implementation
    # @return [Strands::Tools::Definition] the tool definition
    #
    # @example With a block
    #   tool = Strands.tool("reverse", description: "Reverses a string",
    #     schema: { properties: { text: { type: "string" } }, required: ["text"] }
    #   ) { |text:| text.reverse }
    #
    def tool(name, description:, schema: {}, callable: nil, &block)
      Tools::DSL.define_tool(name, description: description, schema: schema, callable: callable, &block)
    end
  end
end
