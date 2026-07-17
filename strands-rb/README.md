# Strands Ruby SDK

A Ruby framework for building, deploying, and managing AI agents. Build powerful AI applications with multi-provider model support, tool execution, lifecycle hooks, and composable plugins -- all with zero external runtime dependencies.

## Features

- **Multi-Provider Models** - Bedrock, OpenAI, Anthropic, and Ollama with a unified streaming interface
- **Tool Framework** - Ruby-native DSL, JSON Schema validation, and MCP protocol support
- **Typed Hook System** - Observe and extend agent behavior with prioritized lifecycle events
- **Intervention Handlers** - Approve, deny, guide, or transform requests at any lifecycle point
- **Plugin System** - Combine hooks and tools into reusable, composable extensions
- **Session Persistence** - Save and restore conversations across agent restarts
- **Cross-Session Memory** - Store and recall facts across multiple conversations
- **Telemetry** - OpenTelemetry-compatible tracing and metrics (no external deps)
- **Zero Dependencies** - Uses only Ruby standard library for runtime operation
- **Streaming-First** - All model providers stream responses in real-time

## Requirements

- Ruby >= 4.0.0
- No external runtime dependencies (stdlib only)

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

### Basic Agent

```ruby
require "strands"

agent = Strands::Agent::Agent.new(
  model: Strands::Models::OpenAI.new(model_id: "gpt-4o"),
  system_prompt: "You are a helpful assistant."
)

result = agent.call("What is the meaning of life?")
puts result.text
```

### Agent with Tools

```ruby
require "strands"

# Define a tool using the DSL
calculator = Strands.tool("calculator",
  description: "Evaluates a mathematical expression",
  schema: {
    properties: {
      expression: { type: "string", description: "Math expression to evaluate" }
    },
    required: ["expression"]
  }
) { |expression:| eval(expression).to_s }

# Create agent with tools
agent = Strands::Agent::Agent.new(
  model: Strands::Models::Bedrock.new(
    model_id: "anthropic.claude-3-5-sonnet-20241022-v2:0"
  ),
  tools: [calculator],
  system_prompt: "You are a math tutor. Use the calculator for computations."
)

result = agent.call("What is 1847 * 293 + 42?")
puts result.text
# => "1847 * 293 + 42 = 541,213"
```

### Multi-Turn Conversation

```ruby
agent = Strands::Agent::Agent.new(
  model: Strands::Models::Anthropic.new(model_id: "claude-3-5-sonnet-20241022"),
  system_prompt: "You are a creative writing assistant."
)

result1 = agent.call("Write a haiku about Ruby programming.")
puts result1.text

result2 = agent.call("Now make it about Python instead.")
puts result2.text
# The agent remembers the previous context
```

### Local Models with Ollama

```ruby
agent = Strands::Agent::Agent.new(
  model: Strands::Models::Ollama.new(model_id: "llama3"),
  system_prompt: "You are a helpful coding assistant."
)

result = agent.call("Write a binary search in Ruby.")
puts result.text
```

## Detailed Usage

### Agent

The `Agent` class is the primary entry point. It orchestrates model calls, tool execution, hooks, and conversation management.

```ruby
agent = Strands::Agent::Agent.new(
  model: model,                    # Model provider (required)
  tools: [tool1, tool2],           # Tools available to the agent
  system_prompt: "...",            # System instructions
  hooks: [my_hook_provider],       # Hook providers
  interventions: [my_handler],     # Intervention handlers
  plugins: [my_plugin],            # Plugins (hooks + tools combined)
  callback_handler: handler,       # Streaming output handler
  conversation_manager: manager,   # Message history management
  retry_strategy: strategy,        # Error retry configuration
  max_turns: 50,                   # Maximum event loop turns
  name: "My Agent"                 # Agent name for telemetry
)

# Primary interface
result = agent.call("user prompt")
result = agent.invoke("user prompt")  # alias

# Access the result
result.text         # The text response
result.message      # Full message hash
result.stop_reason  # :end_turn, :tool_use, :limit_turns, etc.
result.metrics      # Performance metrics hash

# Direct tool invocation (bypasses model)
agent.tool.calculator(expression: "2 + 2")

# Access internals
agent.messages         # Conversation history
agent.tool_registry    # Tool registry
agent.hook_registry    # Hook registry
```

### Models

All model providers implement the same interface (`Strands::Models::Base`):

#### AWS Bedrock

```ruby
model = Strands::Models::Bedrock.new(
  model_id: "anthropic.claude-3-5-sonnet-20241022-v2:0",
  region: "us-west-2",
  access_key_id: ENV["AWS_ACCESS_KEY_ID"],
  secret_access_key: ENV["AWS_SECRET_ACCESS_KEY"],
  session_token: ENV["AWS_SESSION_TOKEN"],  # optional
  temperature: 0.7,
  max_tokens: 4096
)
```

Uses the Converse Stream API with SigV4 authentication. Optionally detects and uses `aws-sdk-bedrockruntime` if available.

#### OpenAI

```ruby
model = Strands::Models::OpenAI.new(
  model_id: "gpt-4o",
  api_key: ENV["OPENAI_API_KEY"],  # or pass explicitly
  base_url: "https://api.openai.com",  # for compatible endpoints
  temperature: 0.7,
  max_tokens: 4096
)
```

Works with any OpenAI-compatible endpoint (Azure OpenAI, vLLM, Anyscale, etc.).

#### Anthropic

```ruby
model = Strands::Models::Anthropic.new(
  model_id: "claude-3-5-sonnet-20241022",
  api_key: ENV["ANTHROPIC_API_KEY"],
  max_tokens: 4096,
  base_url: "https://api.anthropic.com",
  temperature: 0.7
)
```

#### Ollama

```ruby
model = Strands::Models::Ollama.new(
  model_id: "llama3",
  host: "http://localhost:11434",
  temperature: 0.8,
  num_predict: 2048
)
```

Local inference with no API keys needed. Requires Ollama running locally.

#### Runtime Configuration

```ruby
# Update config at runtime
model.update_config(temperature: 0.9, max_tokens: 2048)

# Read current config
config = model.get_config
puts config[:model_id]
```

### Tools

#### DSL (Recommended)

```ruby
weather = Strands.tool("get_weather",
  description: "Get current weather for a city",
  schema: {
    properties: {
      city: { type: "string", description: "City name" },
      units: { type: "string", description: "celsius or fahrenheit" }
    },
    required: ["city"]
  }
) do |city:, units: "celsius"|
  # Your implementation here
  { temperature: 72, condition: "sunny", city: city }
end
```

#### Definition Class

```ruby
definition = Strands::Tools::Definition.new(
  name: "search",
  description: "Search the knowledge base",
  input_schema: {
    type: "object",
    properties: {
      query: { type: "string", description: "Search query" },
      limit: { type: "integer", description: "Max results" }
    },
    required: ["query"]
  },
  callable: ->(query:, limit: 10) {
    # implementation
    [{ title: "Result 1", score: 0.95 }]
  }
)
```

#### Tool Registry

```ruby
registry = Strands::Tools::Registry.new

# Register tools
registry.register(weather_tool)
registry.register(search_tool)

# Lookup
tool = registry.get("get_weather")
tool = registry.fetch("get_weather")  # raises if not found

# List
registry.list        # => ["get_weather", "search"]
registry.size        # => 2
registry.registered?("get_weather")  # => true

# Get specs for model API
specs = registry.tool_specs

# Remove
registry.unregister("get_weather")
registry.clear
```

#### MCP Client

Connect to Model Context Protocol servers:

```ruby
# Stdio transport
client = Strands::Tools::MCPClient.new(
  transport: :stdio,
  command: "npx",
  args: ["-y", "@modelcontextprotocol/server-filesystem", "/home/user"]
)

# HTTP transport
client = Strands::Tools::MCPClient.new(
  transport: :http,
  url: "http://localhost:3000/mcp"
)

# Start the connection
client.start

# List available tools
tools = client.list_tools

# Convert to Strands definitions
definitions = client.to_definitions

# Use with an agent
agent = Strands::Agent::Agent.new(
  model: model,
  tools: definitions
)

# Call a tool directly
result = client.call_tool("read_file", { path: "/etc/hosts" })

# Clean up
client.stop
```

### Hooks

The hook system provides typed lifecycle events with priority ordering:

```ruby
# Create a hook provider
class LoggingProvider
  include Strands::Hooks::Provider

  def register_hooks(registry)
    registry.add_callback(
      Strands::Hooks::BeforeModelCallEvent,
      order: Strands::Hooks::HookOrder::DEFAULT
    ) do |event|
      puts "[LOG] Model call starting for #{event.agent.name}"
    end

    registry.add_callback(
      Strands::Hooks::AfterToolCallEvent,
      order: Strands::Hooks::HookOrder::DEFAULT
    ) do |event|
      tool_name = event.tool_use.name
      puts "[LOG] Tool '#{tool_name}' completed"
    end
  end
end

# Use with agent
agent = Strands::Agent::Agent.new(
  model: model,
  hooks: [LoggingProvider.new]
)
```

#### Available Events

| Event | Fired When |
|-------|-----------|
| `AgentInitializedEvent` | Agent construction complete |
| `BeforeInvocationEvent` | Before `agent.call()` processes |
| `AfterInvocationEvent` | After `agent.call()` completes |
| `BeforeModelCallEvent` | Before model streaming begins |
| `AfterModelCallEvent` | After model response collected |
| `BeforeToolCallEvent` | Before tool execution |
| `AfterToolCallEvent` | After tool execution |
| `MessageAddedEvent` | Message added to history |

#### Hook Priority

```ruby
Strands::Hooks::HookOrder::SDK_FIRST         # -100
Strands::Hooks::HookOrder::INTERVENTION_OUTPUT # -90
Strands::Hooks::HookOrder::BEFORE            # -50
Strands::Hooks::HookOrder::DEFAULT           #   0
Strands::Hooks::HookOrder::AFTER             #  50
Strands::Hooks::HookOrder::INTERVENTION_INPUT #  90
Strands::Hooks::HookOrder::SDK_LAST          # 100
```

### Interventions

Interventions let you approve, deny, guide, or transform operations:

```ruby
class SafetyHandler < Strands::Interventions::Handler
  def name
    "safety-check"
  end

  def before_tool_call(event)
    tool_name = event.tool_use.name

    if dangerous_tool?(tool_name)
      Strands::Interventions::Deny.new(
        reason: "Tool '#{tool_name}' is not allowed"
      )
    else
      Strands::Interventions::Proceed.new
    end
  end

  def before_invocation(event)
    Strands::Interventions::Guide.new(
      feedback: "Remember to be concise and factual."
    )
  end

  private

  def dangerous_tool?(name)
    %w[delete_file execute_command].include?(name)
  end
end

agent = Strands::Agent::Agent.new(
  model: model,
  interventions: [SafetyHandler.new]
)
```

#### Action Types

| Action | Effect |
|--------|--------|
| `Proceed` | Allow operation to continue |
| `Deny` | Block operation, communicate reason to model |
| `Guide` | Provide steering feedback to model |
| `Transform` | Mutate event data via a callable |

```ruby
# Transform example
Strands::Interventions::Transform.new(
  apply: ->(event) { event.tool_use.input[:safe_mode] = true },
  reason: "Injecting safe mode flag"
)
```

### Plugins

Plugins combine hooks and tools into reusable units:

```ruby
class AuditPlugin
  include Strands::Plugins::Base

  plugin_name "audit"

  # Declare a hook
  hook :log_model_call, event: Strands::Hooks::BeforeModelCallEvent
  def log_model_call(event)
    @calls ||= []
    @calls << { time: Time.now, agent: event.agent.name }
  end

  # Declare a tool
  plugin_tool :get_audit_log,
    description: "Retrieve the audit log",
    schema: { properties: {}, required: [] }
  def get_audit_log(_params)
    (@calls || []).map { |c| "#{c[:time]}: #{c[:agent]}" }.join("\n")
  end
end

agent = Strands::Agent::Agent.new(
  model: model,
  plugins: [AuditPlugin.new]
)
```

### Storage

Persistence backends for key-value data:

#### InMemory Storage

```ruby
storage = Strands::Storage::InMemory.new

storage.write("sessions/abc/state.json", '{"messages": []}')
data = storage.read("sessions/abc/state.json")   # => '{"messages": []}'
storage.exists?("sessions/abc/state.json")       # => true
storage.list("sessions/")                        # => ["sessions/abc/state.json"]
storage.delete("sessions/abc/state.json")
storage.size                                     # => 0
```

#### LocalFile Storage

```ruby
storage = Strands::Storage::LocalFile.new(base_dir: "./.strands/data")

# Same interface as InMemory, but persists to filesystem
storage.write("config/settings.json", '{"debug": true}')
data = storage.read("config/settings.json")

# Writes are atomic (temp file + rename)
# Keys map to file paths under base_dir
```

### Session Management

Persist conversations across agent restarts:

```ruby
# File-based sessions
session_manager = Strands::Session::FileManager.new(
  base_dir: "./.strands/sessions",
  session_id: "user-123-chat"  # auto-generated if nil
)

agent = Strands::Agent::Agent.new(
  model: model,
  hooks: [session_manager]  # Session managers are hook providers
)

# First invocation - starts fresh
result = agent.call("Hello!")

# Later, create a new agent with same session_id to restore
agent2 = Strands::Agent::Agent.new(
  model: model,
  hooks: [Strands::Session::FileManager.new(
    base_dir: "./.strands/sessions",
    session_id: "user-123-chat"
  )]
)
# agent2.messages is restored from the session file
result = agent2.call("What did I say before?")
```

### Memory

Cross-session fact storage and retrieval:

```ruby
# Create a memory store
facts_store = Strands::Memory::InMemoryStore.new(
  name: "user-facts",
  description: "Known facts about the user"
)

# Create the memory manager (acts as a plugin)
memory = Strands::Memory::Manager.new(
  stores: [facts_store],
  default_max_results: 5
)

# Use with agent - exposes search_memory and add_memory as tools
agent = Strands::Agent::Agent.new(
  model: model,
  plugins: [memory]
)

# Or use programmatically
memory.add("User prefers dark mode", metadata: { category: "preferences" })
results = memory.search("dark mode")
results.each { |entry| puts "#{entry.content} (#{entry.store_name})" }
```

### Telemetry

#### Tracer

OpenTelemetry-compatible span tracing:

```ruby
tracer = Strands::Telemetry::Tracer.new(service_name: "my-agent")

# Manual spans
span = tracer.start_span("custom_operation", attributes: { "key" => "value" })
# ... do work ...
tracer.end_span(span)

# Convenience methods
model_span = tracer.start_model_span("gpt-4o")
tool_span = tracer.start_tool_span("calculator", tool_use_id: "call_123")
cycle_span = tracer.start_cycle_span("cycle-1")
agent_span = tracer.start_agent_span("My Agent", model_id: "gpt-4o")

# Error handling
begin
  # risky operation
rescue => e
  tracer.end_span(span, error: e)
end

# Global tracer
Strands::Telemetry.tracer  # shared instance
```

#### Metrics

Token usage and performance tracking:

```ruby
metrics = Strands::Telemetry::Metrics.new

metrics.start_invocation
metrics.record_usage(input_tokens: 150, output_tokens: 50)
metrics.record_latency(234.5)
metrics.record_tool_call("calculator", duration: 0.05, success: true)
metrics.record_cycle(duration: 1.2)

summary = metrics.summary
# => { total_input_tokens: 150, total_output_tokens: 50, ... }

# Per-tool metrics
metrics.tool_metrics["calculator"].call_count     # => 1
metrics.tool_metrics["calculator"].success_rate   # => 1.0
metrics.tool_metrics["calculator"].average_duration # => 0.05
```

## Configuration Reference

### Agent Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `model` | Object | `nil` | Model provider (must implement `Models::Base`) |
| `tools` | Array | `[]` | Tools to register |
| `system_prompt` | String | `nil` | System instructions for the model |
| `hooks` | Array | `[]` | Hook providers |
| `interventions` | Array | `[]` | Intervention handlers |
| `plugins` | Array | `[]` | Plugins (hooks + tools) |
| `callback_handler` | Object | `nil` | Streaming output handler |
| `conversation_manager` | Object | `nil` | Message history manager |
| `retry_strategy` | RetryStrategy | default | Retry configuration |
| `max_turns` | Integer | `50` | Max event loop turns |
| `name` | String | `"Strands Agent"` | Agent name |

### RetryStrategy Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `max_attempts` | Integer | `6` | Max retry attempts |
| `initial_delay` | Float | `4.0` | Initial backoff delay (seconds) |
| `max_delay` | Float | `240.0` | Maximum delay cap (seconds) |
| `backoff_factor` | Float | `2.0` | Exponential backoff multiplier |

### Callback Handlers

```ruby
# Print streaming output (default behavior)
handler = Strands::Handlers::Printing.new(
  output: $stdout,
  verbose_tool_use: true
)

# Silent (no output)
handler = Strands::Handlers::Null.new

# Custom
handler = ->(data:, complete: false, **kwargs) {
  print data if data
  puts "" if complete
}
```

## Architecture Overview

```
Agent#call(prompt)
  |
  +-> Hooks: BeforeInvocationEvent
  +-> Add user message to conversation
  +-> ConversationManager: trim/window messages
  +-> EventLoop::Cycle
  |     |
  |     +-> Hooks: BeforeModelCallEvent
  |     +-> Model#stream -> yields StreamEvents
  |     +-> Hooks: AfterModelCallEvent
  |     +-> If tool_use: execute tools, loop back
  |     +-> If end_turn: return result
  |
  +-> Hooks: AfterInvocationEvent
  +-> Return Result
```

For detailed architecture documentation, see [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Provider Guides

- [AWS Bedrock](docs/providers/BEDROCK.md) - Setup, credentials, model IDs
- [OpenAI](docs/providers/OPENAI.md) - API key, compatible endpoints
- [Anthropic](docs/providers/ANTHROPIC.md) - Claude models, max_tokens
- [Ollama](docs/providers/OLLAMA.md) - Local inference, model management

## Development

```bash
# Run tests
bundle exec rspec

# Run specific test file
bundle exec rspec spec/strands/models/openai_spec.rb

# Run linter
bundle exec rubocop

# Validate syntax
ruby -c lib/strands/models/openai.rb

# Generate documentation
bundle exec yard doc
```

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feat/my-feature`)
3. Make your changes following the coding conventions
4. Add tests for new functionality
5. Ensure all tests pass (`bundle exec rspec`)
6. Ensure code style is clean (`bundle exec rubocop`)
7. Commit with conventional format (`feat: add new feature`)
8. Push and open a pull request

See [AGENTS.md](AGENTS.md) for detailed development guidelines and [CLAUDE.md](CLAUDE.md) for AI agent-specific guidance.

## License

Apache-2.0. See [LICENSE](LICENSE) for details.
