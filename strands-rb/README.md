# Strands Ruby SDK

A framework for building, deploying, and managing AI agents in Ruby.

## Overview

Strands provides a composable framework for building AI agents with support for:

- Multiple model providers (Bedrock, OpenAI, Anthropic, Ollama, and more)
- Tool execution with a Ruby-native DSL
- Typed hook system for lifecycle events
- Intervention handlers for request/response modification
- Session and memory management
- OpenTelemetry observability

## Installation

Add to your Gemfile:

```ruby
gem "strands"
```

Or install directly:

```bash
gem install strands
```

## Quick Start

```ruby
require "strands"

# Define a tool
calculator = Strands::Tools.define(:calculator, description: "Performs arithmetic") do |input|
  eval(input[:expression]).to_s
end

# Create an agent
agent = Strands::Agent::Agent.new(
  model: Strands::Models::Bedrock.new(model_id: "anthropic.claude-3-5-sonnet-20241022-v2:0"),
  tools: [calculator],
  system_prompt: "You are a helpful math assistant."
)

# Invoke the agent
result = agent.call("What is 42 * 17?")
puts result.message
```

## Architecture

The SDK is organized into focused modules:

| Module | Purpose |
|--------|---------|
| `Strands::Agent` | Core agent class with conversation management |
| `Strands::Models` | Model provider interface and implementations |
| `Strands::Tools` | Tool registry, execution, and DSL |
| `Strands::EventLoop` | Turn cycle orchestration and streaming |
| `Strands::Hooks` | Typed event callbacks for lifecycle events |
| `Strands::Interventions` | Request/response modification handlers |
| `Strands::Plugins` | Composable plugin system |
| `Strands::Storage` | Persistence backends (memory, file, S3) |
| `Strands::Session` | Session lifecycle management |
| `Strands::Memory` | Cross-session fact recall |
| `Strands::Telemetry` | OpenTelemetry tracing and metrics |

## Requirements

- Ruby >= 3.2.0 (targets Ruby 4.0.6)
- No external runtime dependencies (stdlib only)

## Development

```bash
# Run tests
bundle exec rspec

# Run linter
bundle exec rubocop

# Run all checks
bundle exec rake check
```

## License

Apache-2.0. See [LICENSE](LICENSE) for details.
