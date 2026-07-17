# CLAUDE.md - Steering for Claude AI Agents

This document provides context and guidance for Claude AI agents working on the Strands Ruby SDK codebase.

## Project Overview

Strands Ruby SDK (`strands-rb`) is a Ruby framework for building, deploying, and managing AI agents. It aims for feature parity with the Python Strands SDK while being idiomatic Ruby. The SDK provides:

- Multi-provider model abstraction (Bedrock, OpenAI, Anthropic, Ollama)
- Tool execution framework with DSL and MCP protocol support
- Typed hook system for lifecycle observation
- Intervention handlers for request/response modification
- Plugin system combining hooks and tools
- Session persistence and cross-session memory
- OpenTelemetry-compatible telemetry (no external deps)

**Critical constraint:** No external runtime dependencies. The SDK uses only Ruby stdlib.

## Directory Structure

```
strands-rb/
  lib/
    strands.rb                    # Root file with autoloads
    strands/
      agent/
        agent.rb                  # Main Agent class (orchestrator)
        agent_result.rb           # Result struct from agent invocations
        conversation_manager.rb   # Message history windowing
      models/
        base.rb                   # Model interface module
        stream_event_builder.rb   # Shared event construction
        bedrock.rb                # AWS Bedrock provider
        openai.rb                 # OpenAI/compatible provider
        anthropic.rb              # Anthropic Claude provider
        ollama.rb                 # Local Ollama provider
      tools/
        definition.rb             # Tool definition wrapper
        registry.rb               # Central tool registry
        executor.rb               # Tool execution with context
        dsl.rb                    # Strands.tool() convenience
        mcp_client.rb             # MCP protocol client
        tool_context.rb           # Context struct for tools
        tool_provider.rb          # Interface for tool providers
      event_loop/
        cycle.rb                  # Main turn-processing loop
        retry.rb                  # Exponential backoff strategy
      hooks/
        registry.rb               # Callback registry with priorities
        events.rb                 # All event type definitions
        provider.rb               # Interface for hook providers
      interventions/
        handler.rb                # Base intervention handler
        registry.rb               # Bridges handlers to hooks
        actions.rb                # Proceed, Deny, Guide, Transform
      plugins/
        base.rb                   # Plugin module with DSL
        discovery.rb              # Hook/tool method scanning
      handlers/
        callback_handler.rb       # Base callback handler
        printing.rb               # Prints streaming output
        null.rb                   # Silent no-op handler
      storage/
        base.rb                   # Storage interface module
        in_memory.rb              # Hash-backed storage
        local_file.rb             # Filesystem storage
      session/
        session_manager.rb        # Abstract session manager
        file_session_manager.rb   # File-backed sessions
      memory/
        memory_manager.rb         # Multi-store coordinator (plugin)
        memory_store.rb           # Store interface module
        in_memory_store.rb        # Simple substring-match store
        types.rb                  # MemoryEntry, SearchOptions
      telemetry/
        tracer.rb                 # Span-based tracer
        metrics.rb                # Token/latency/tool metrics
      types/
        content.rb                # Messages, ContentBlocks
        tools.rb                  # ToolSpec, ToolUse, ToolResult
        media.rb                  # Image, Document, Video types
        event_loop.rb             # Usage, Metrics structs
        streaming.rb              # StreamEvent types
        exceptions.rb             # Custom error classes
  spec/
    spec_helper.rb
    strands/
      models/
        openai_spec.rb
        ollama_spec.rb
        bedrock_spec.rb
        anthropic_spec.rb
      tools/
        mcp_client_spec.rb
  docs/
    ARCHITECTURE.md
    providers/
      BEDROCK.md
      OPENAI.md
      ANTHROPIC.md
      OLLAMA.md
```

## Coding Conventions

### Mandatory File Header

Every Ruby file MUST start with:
```ruby
# frozen_string_literal: true
```

### YARD Documentation

All public methods and classes MUST have YARD documentation:
```ruby
# Brief description of the method.
#
# @param name [Type] description
# @param options [Hash] description
# @option options [String] :key description
# @return [Type] description
# @raise [ErrorType] when condition
# @example
#   result = method_name(arg)
#
def method_name(name, options: {})
```

### Module Nesting Pattern

Always use explicit module nesting (not compact `::` notation):
```ruby
module Strands
  module Models
    class OpenAI
      # ...
    end
  end
end
```

### No External Runtime Dependencies

The SDK MUST NOT add external gems to runtime dependencies. All functionality uses Ruby stdlib:
- `net/http` for HTTP requests
- `json` for JSON parsing
- `openssl` for cryptography (SigV4 signing)
- `securerandom` for UUID/ID generation
- `uri` for URL parsing
- `fileutils` for filesystem operations
- `monitor` for thread-safe data structures
- `time` for ISO 8601 formatting

Development dependencies (RSpec, RuboCop) are acceptable.

### Naming Conventions

- Classes: `PascalCase`
- Methods: `snake_case`
- Constants: `SCREAMING_SNAKE_CASE`
- Predicate methods: end with `?` (e.g., `exists?`, `recording?`)
- Destructive methods: end with `!` (e.g., `reset!`, `clear!`)
- Private methods: indented under `private` keyword, no underscore prefix

### Error Handling

- Use custom exception classes from `types/exceptions.rb`
- Model errors: `ModelError`, `ModelThrottledError`, `ContextWindowOverflowError`
- Validation: `ArgumentError` for bad inputs
- Interface violations: `NotImplementedError`

## Testing Patterns

### Framework

RSpec 3.13 with standard expectations and mocking.

### Structure

Specs mirror the `lib/` directory structure:
```
spec/strands/models/openai_spec.rb  -> lib/strands/models/openai.rb
```

### HTTP Mocking

Model specs mock `Net::HTTP` using helpers:

```ruby
def stub_http_streaming(response_body_chunks)
  http = instance_double(Net::HTTP)
  response = instance_double(Net::HTTPResponse)

  allow(Net::HTTP).to receive(:new).and_return(http)
  allow(http).to receive(:use_ssl=)
  allow(http).to receive(:open_timeout=)
  allow(http).to receive(:read_timeout=)
  allow(http).to receive(:start).and_yield(http)

  allow(response).to receive(:code).and_return("200")
  allow(response).to receive(:body).and_return("")
  allow(http).to receive(:request) do |_req, &block|
    response_body_chunks.each { |chunk| block.call(chunk) } if block
    response
  end

  [http, response]
end

def stub_http_error(status_code, body = "")
  http = instance_double(Net::HTTP)
  response = instance_double(Net::HTTPResponse)

  allow(Net::HTTP).to receive(:new).and_return(http)
  allow(http).to receive(:use_ssl=)
  allow(http).to receive(:open_timeout=)
  allow(http).to receive(:read_timeout=)
  allow(http).to receive(:start).and_yield(http)

  allow(response).to receive(:code).and_return(status_code.to_s)
  allow(response).to receive(:body).and_return(body)
  allow(http).to receive(:request).and_return(response)

  [http, response]
end
```

### Event Collection Helper

```ruby
def collect_events(model, messages, **opts)
  events = []
  model.stream(messages, **opts) { |event| events << event }
  events
end
```

### Spec Organization

```ruby
RSpec.describe Strands::Models::OpenAI do
  let(:model) { described_class.new(model_id: "gpt-4o", api_key: "test-key") }

  describe "#initialize" do
    # config storage, defaults, ENV fallback
  end

  describe "#update_config" do
    # merges config
  end

  describe "#get_config" do
    # returns copy
  end

  describe "#stream" do
    context "with a successful text response" do
      # happy path
    end

    context "with tool use" do
      # tool call detection
    end

    context "when rate limited (429)" do
      # raises ModelThrottledError
    end

    context "when context overflows" do
      # raises ContextWindowOverflowError
    end
  end
end
```

## Architecture Overview

```
Agent#call(prompt)
  -> BeforeInvocationEvent (hooks/interventions)
  -> Add user message
  -> ConversationManager#apply (trim)
  -> EventLoop::Cycle#run
       -> BeforeModelCallEvent
       -> Model#stream (yields StreamEvents)
       -> AfterModelCallEvent
       -> If stop_reason == :tool_use:
            -> BeforeToolCallEvent
            -> Executor#execute
            -> AfterToolCallEvent
            -> Loop back to model
       -> If stop_reason == :end_turn:
            -> Return result
  -> AfterInvocationEvent
  -> Return Result
```

## How to Add a New Model Provider

1. Create `lib/strands/models/your_provider.rb`
2. Include both `Base` and `StreamEventBuilder`:
   ```ruby
   class YourProvider
     include Base
     include StreamEventBuilder
   end
   ```
3. Implement `#initialize` storing config in `@config` hash
4. Implement `#stream(messages, system_prompt:, tools:, tool_choice:, **kwargs)`:
   - Format the request
   - Make HTTP request with streaming
   - Parse streaming chunks
   - Yield normalized `StreamEvent` objects using `build_stream_event`
   - Handle errors (raise `ModelThrottledError`, `ContextWindowOverflowError`, etc.)
5. Implement `#update_config(**opts)` - merge into @config
6. Implement `#get_config` - return @config.dup
7. Add `#inspect` that redacts sensitive config (API keys)
8. Create corresponding spec file following existing patterns
9. Add autoload entry in `lib/strands.rb` (if the file uses `autoload`)

## How to Add Tools

### Via DSL

```ruby
my_tool = Strands.tool("tool_name",
  description: "What it does",
  schema: {
    properties: {
      param1: { type: "string", description: "..." }
    },
    required: ["param1"]
  }
) { |param1:| "result" }
```

### Via Definition

```ruby
definition = Strands::Tools::Definition.new(
  name: "tool_name",
  description: "What it does",
  input_schema: { properties: {...}, required: [...] },
  callable: ->(param1:) { "result" }
)
```

### Via MCP Client

```ruby
client = Strands::Tools::MCPClient.new(
  transport: :stdio,
  command: "npx",
  args: ["-y", "@modelcontextprotocol/server-filesystem", "/path"]
)
client.start
definitions = client.to_definitions
```

## Key Abstractions

- **Base module pattern**: `Models::Base`, `Storage::Base`, `Memory::Store` define interfaces via `include`
- **StreamEventBuilder**: shared module for constructing normalized streaming events
- **Registry pattern**: `Tools::Registry`, `Hooks::Registry`, `Interventions::Registry`
- **Hook system**: typed events with priority ordering and reverse-order cleanup
- **Plugin DSL**: `hook :method, event: Class` and `plugin_tool :method, description: "..."`

## Common Pitfalls

1. **Thread safety**: Agent is NOT thread-safe. Do not share agents across threads.
2. **Keyword arguments**: Tool callables receive keyword arguments, not positional. Ensure tool schemas match parameter names.
3. **Hook ordering**: "After" events fire callbacks in reverse order within same priority group.
4. **Intervention short-circuit**: `Deny` stops all subsequent handlers. `Guide` accumulates.
5. **Storage keys**: Keys use `/` separators and must not contain `..` segments.
6. **frozen_string_literal**: Missing this pragma will cause style violations.

## Build and Test Commands

```bash
# Syntax validation (always works, no deps needed)
ruby -c lib/strands/models/openai.rb

# Run full test suite
bundle exec rspec

# Run specific spec
bundle exec rspec spec/strands/models/openai_spec.rb

# Lint
bundle exec rubocop

# All checks
bundle exec rake check
```
