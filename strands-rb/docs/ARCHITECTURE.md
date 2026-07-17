# Strands Ruby SDK Architecture

## High-Level Overview

```
                          +--------------------+
                          |      Agent         |
                          | (Orchestrator)     |
                          +--------+-----------+
                                   |
                    +--------------+--------------+
                    |                             |
           +--------v--------+          +--------v--------+
           |   Event Loop    |          |  Tool Registry  |
           |   (Cycle)       |          |  (Registry)     |
           +--------+--------+          +--------+--------+
                    |                             |
         +----------+----------+        +---------+--------+
         |                     |        |                  |
+--------v--------+   +--------v----+   |  +--------+     |
|  Model Provider |   | Retry       |   |  | DSL    |     |
|  (stream)       |   | Strategy    |   |  +--------+     |
+-----------------+   +-------------+   |  | MCP    |     |
                                        |  +--------+     |
                                        +--+-----------+--+
                                           | Definition |
                                           +------------+

       +------------+     +--------------+     +-------------+
       |   Hooks    |     | Interventions|     |   Plugins   |
       | (Registry) |     | (Handler)    |     |   (Base)    |
       +------------+     +--------------+     +-------------+

       +------------+     +--------------+     +-------------+
       |  Storage   |     |   Session    |     |   Memory    |
       | (Base)     |     | (Manager)    |     | (Manager)   |
       +------------+     +--------------+     +-------------+

       +-------------------------------------------+
       |              Telemetry                     |
       |         (Tracer + Metrics)                 |
       +-------------------------------------------+
```

## Data Flow

The complete lifecycle of a user prompt through the system:

```
User Prompt
     |
     v
+----+----+
|  Agent  |------> BeforeInvocationEvent (hooks + interventions)
|  #call  |
+----+----+
     |
     v  (add user message to conversation)
+----+----+
| Convers.|------> ConversationManager#apply (trim/window messages)
| Manager |
+----+----+
     |
     v
+----+--------+
| Event Loop  |
|   Cycle     |<----------------------------+
+----+--------+                              |
     |                                       |
     v                                       |
BeforeModelCallEvent                         |
     |                                       |
     v                                       |
+----+--------+                              |
|    Model    |---> HTTP streaming request   |
|   #stream   |                              |
+----+--------+                              |
     |                                       |
     v  (yields StreamEvents)                |
+----+--------+                              |
| Collect     |                              |
| Response    |                              |
+----+--------+                              |
     |                                       |
     v                                       |
AfterModelCallEvent                          |
     |                                       |
     +----> stop_reason == :end_turn? -----> Result
     |               (yes)
     v (no, stop_reason == :tool_use)
+----+--------+
| Tool        |
| Detection   |
+----+--------+
     |
     v
BeforeToolCallEvent
     |
     v
+----+--------+
|    Tool     |
|  Executor   |
+----+--------+
     |
     v
AfterToolCallEvent
     |
     v  (append tool results to messages)
     +------------------------------------->+ (loop back to model)
```

## Module Descriptions

### Agent (`Strands::Agent`)

The primary entry point. `Agent::Agent` orchestrates the entire system:
- Maintains conversation history (`@messages` array)
- Owns the tool registry, hook registry, and intervention registry
- Delegates turn processing to `EventLoop::Cycle`
- Provides `#call(prompt)` and `#invoke(prompt)` for interaction
- Offers `#tool` proxy for direct tool invocation

Key classes:
- `Agent::Agent` - main agent class
- `Agent::Result` - structured response from an invocation
- `Agent::ConversationManager` - message history windowing/trimming
- `Agent::ToolCaller` - proxy for direct tool execution

### Models (`Strands::Models`)

Abstraction layer for LLM providers. Each provider implements the `Base` module interface.

Key interface methods:
- `#stream(messages, system_prompt:, tools:, tool_choice:)` - stream model responses
- `#update_config(**opts)` - update runtime configuration
- `#get_config` - retrieve current configuration

Providers:
- `Bedrock` - AWS Bedrock Converse Stream API (SigV4 auth, optional SDK)
- `OpenAI` - OpenAI Chat Completions API (SSE streaming)
- `Anthropic` - Anthropic Messages API (SSE streaming)
- `Ollama` - Local Ollama chat API (NDJSON streaming)

Shared concerns:
- `StreamEventBuilder` - module for constructing normalized `StreamEvent` objects
- All providers stream responses and yield `StreamEvent` instances

### Tools (`Strands::Tools`)

Tool management and execution framework.

Key classes:
- `Definition` - wraps a callable with name, description, and JSON Schema
- `Registry` - central store for all tools available to an agent
- `Executor` - invokes tools with proper context injection
- `DSL` - `Strands.tool("name", ...)` convenience method
- `MCPClient` - Model Context Protocol client (stdio and HTTP transports)
- `ToolContext` - framework context injected into tool calls
- `ToolProvider` - interface for objects that provide tools

### EventLoop (`Strands::EventLoop`)

The turn-processing engine that loops between model calls and tool execution.

Key classes:
- `Cycle` - implements the main loop (model call -> tool detect -> execute -> repeat)
- `RetryStrategy` - exponential backoff with jitter for transient errors

The cycle continues until:
1. Model returns `stop_reason: :end_turn` (conversation complete)
2. Maximum turns reached (`DEFAULT_MAX_TURNS = 50`)
3. An intervention denies the model call

### Hooks (`Strands::Hooks`)

Typed event system for observing and extending agent behavior.

Key classes:
- `Registry` - manages callbacks per event type with priority ordering
- `Provider` - module interface for hook providers
- `HookOrder` - priority constants (SDK_FIRST, BEFORE, DEFAULT, AFTER, SDK_LAST)

Event types:
- `AgentInitializedEvent` - agent setup complete
- `BeforeInvocationEvent` / `AfterInvocationEvent` - request lifecycle
- `BeforeModelCallEvent` / `AfterModelCallEvent` - model interaction
- `BeforeToolCallEvent` / `AfterToolCallEvent` - tool execution
- `MessageAddedEvent` - conversation history updates

Design decisions:
- "After" events use reverse callback ordering for cleanup semantics
- Priority ordering via `HookOrder` constants enables deterministic execution
- Events are passed by reference; hooks can mutate accessible attributes

### Interventions (`Strands::Interventions`)

Request/response modification layer that integrates with the hook system.

Key classes:
- `Handler` - base class for intervention handlers (override lifecycle methods)
- `Registry` - bridges handlers to the hook system
- Actions: `Proceed`, `Deny`, `Guide`, `Transform`

Action semantics:
- `Proceed` - allow operation to continue unchanged
- `Deny` - block the operation, communicate reason to model
- `Guide` - provide feedback to steer model behavior
- `Transform` - mutate event data in-place via a callable

Handlers are evaluated in registration order with short-circuit on `Deny`.

### Plugins (`Strands::Plugins`)

Composable extension system combining hooks and tools in a single unit.

Key modules/classes:
- `Base` - include in any plugin class for auto-discovery of hooks and tools
- `Discovery` - class hierarchy scanning for hook/tool declarations

Plugin DSL:
- `plugin_name "my-plugin"` - set plugin identifier
- `hook :method, event: EventClass` - declare a hook callback
- `plugin_tool :method, description: "..."` - declare a tool

### Storage (`Strands::Storage`)

Persistence abstraction for key-value data.

Key interface (`Base` module):
- `#read(key)` - read data
- `#write(key, data)` - write data (atomic for LocalFile)
- `#delete(key)` - remove data
- `#exists?(key)` - check existence
- `#list(prefix)` - list keys by prefix

Implementations:
- `InMemory` - hash-backed, thread-safe via MonitorMixin
- `LocalFile` - filesystem-backed with atomic writes (temp + rename)

### Session (`Strands::Session`)

Conversation persistence across agent restarts.

Key classes:
- `Manager` - abstract base implementing `Hooks::Provider`
- `FileManager` - file-backed session using `Storage::LocalFile`

Session managers hook into:
- `AgentInitializedEvent` - restore state
- `MessageAddedEvent` - persist messages
- `AfterInvocationEvent` - sync full state

### Memory (`Strands::Memory`)

Cross-session fact storage and retrieval.

Key classes:
- `Manager` - coordinates multiple stores, exposes as plugin tools
- `Store` (module) - interface for memory backends
- `InMemoryStore` - simple substring-match implementation
- `MemoryEntry` - data container for stored facts
- `SearchOptions` - configuration for search operations

### Telemetry (`Strands::Telemetry`)

Observability without external dependencies.

Key classes:
- `Tracer` - creates spans for agent operations (OpenTelemetry-compatible API)
- `Span` - represents a single trace span with attributes and events
- `Metrics` - tracks token usage, latency, tool call stats per invocation
- `ToolMetric` - per-tool statistics
- `InvocationMetric` - per-invocation statistics

### Types (`Strands::Types`)

Shared type definitions used across the SDK.

Sub-modules:
- `Content` - messages, content blocks, system prompts
- `Tools` - tool specs, tool use requests, tool results, tool config
- `Media` - images, documents, videos (source types)
- `EventLoop` - Usage, Metrics structs, stop reasons
- `Streaming` - StreamEvent and related types
- `Exceptions` - custom error classes

## Extension Points

### Adding a New Model Provider

1. Create a class under `lib/strands/models/`
2. Include `Strands::Models::Base` and `Strands::Models::StreamEventBuilder`
3. Implement `#stream(messages, system_prompt:, tools:, tool_choice:, **kwargs)`
4. Implement `#update_config(**opts)` and `#get_config`
5. Yield `StreamEvent` objects via the `build_stream_event` helper
6. Handle errors by raising appropriate exception types

### Adding a New Tool

Option A - DSL:
```ruby
my_tool = Strands.tool("name", description: "...", schema: {...}) do |params|
  # implementation
end
```

Option B - Definition:
```ruby
definition = Strands::Tools::Definition.new(
  name: "name",
  description: "...",
  input_schema: {...},
  callable: ->(params) { ... }
)
```

### Adding Custom Hooks

Implement `Hooks::Provider`:
```ruby
class MyHookProvider
  include Strands::Hooks::Provider

  def register_hooks(registry)
    registry.add_callback(Strands::Hooks::BeforeModelCallEvent) do |event|
      # your logic
    end
  end
end
```

### Adding Interventions

Subclass `Interventions::Handler`:
```ruby
class MyIntervention < Strands::Interventions::Handler
  def name = "my-intervention"

  def before_tool_call(event)
    # Return Proceed, Deny, Guide, or Transform
  end
end
```

### Adding Storage Backends

Include `Storage::Base` and implement the required methods:
```ruby
class MyStorage
  include Strands::Storage::Base

  def read(key) ... end
  def write(key, data) ... end
  def delete(key) ... end
  def exists?(key) ... end
  def list(prefix = "") ... end
end
```

## Thread Safety

**Agent is NOT thread-safe.** The `@messages` array and the conversation manager perform non-atomic read-modify-write sequences. Each thread must use its own Agent instance, or external synchronization (e.g., a Mutex) must be applied around calls.

Thread-safe components:
- `Storage::InMemory` (uses MonitorMixin)
- `Storage::LocalFile` (atomic writes via temp-and-rename)
- `Memory::InMemoryStore` (uses MonitorMixin)

## Design Principles

1. **No external runtime dependencies** - The SDK uses only Ruby stdlib. Optional integrations (aws-sdk-bedrockruntime) are detected at runtime but never required.

2. **Stdlib only** - net/http for HTTP, json for parsing, securerandom for IDs, openssl for SigV4. No Faraday, no HTTParty, no external JSON libraries.

3. **Lazy loading via autoload** - Modules use `autoload` to defer loading until first access. This keeps startup time minimal and memory usage low.

4. **Streaming-first** - All model providers implement streaming. Events are yielded as they arrive from the model, enabling real-time output.

5. **Composable architecture** - Hooks, interventions, plugins, tools, and storage are all independent. Mix and match to build exactly the agent you need.

6. **Convention over configuration** - Sensible defaults for everything. An agent with zero configuration (just a model) works out of the box.

7. **Ruby-idiomatic** - Blocks, keyword arguments, module mixins, method_missing proxies. The API feels natural to Ruby developers.
