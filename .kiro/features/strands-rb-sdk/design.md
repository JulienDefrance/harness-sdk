# Strands Ruby SDK - Architecture & Design

## Overview

This document describes how the Python Strands SDK architecture maps to Ruby idioms,
and the key design decisions for the Ruby implementation.

---

## 1. Module Structure

```
Strands
  ::Agent          - Core agent class (callable via #call)
  ::Models         - Model provider base and implementations
    ::Base         - Abstract base model
    ::Bedrock      - AWS Bedrock provider
    ::OpenAI       - OpenAI provider
    ::Anthropic    - Anthropic provider
    ::Ollama       - Ollama local models
    ::Gemini       - Google Gemini
    ::LiteLLM      - Multi-provider proxy
    ::LlamaCpp     - Local GGUF models
    ::Mistral      - Mistral AI
    ::SageMaker    - AWS SageMaker
    ::Writer       - Writer AI
  ::Tools          - Tool system (registry, execution, DSL)
    ::Registry     - Tool registration and lookup
    ::Executor     - Sequential/concurrent execution
    ::MCP          - Model Context Protocol client
    ::DSL          - Tool definition helpers
  ::EventLoop      - Event loop orchestration
    ::Cycle        - Single turn cycle logic
    ::Streaming    - Stream event handling
    ::Retry        - Retry strategy with backoff
  ::Types          - Shared type definitions
    ::Content      - Content block structures
    ::Streaming    - Stream event types
    ::Exceptions   - Custom exception classes
  ::Hooks          - Typed hook/event system
    ::Events       - Event class definitions
    ::Registry     - Hook registration and dispatch
  ::Interventions  - Request/response intervention
    ::Actions      - Proceed, Deny, Guide, Transform, Confirm
    ::Handler      - Base handler class
    ::Registry     - Handler composition and dispatch
  ::Plugins        - Plugin system
    ::Base         - Plugin interface
    ::Registry     - Plugin management
  ::Handlers       - Legacy callback handlers
    ::Printing     - Stdout printing handler
    ::Null         - No-op handler
  ::Memory         - Cross-session memory
    ::Manager      - Memory lifecycle
    ::Extraction   - Fact extraction from conversations
  ::Storage        - Persistence backends
    ::Base         - Storage interface
    ::InMemory     - Hash-based storage
    ::LocalFile    - Filesystem storage
    ::S3           - AWS S3 storage
  ::Session        - Session management
    ::Manager      - Session CRUD interface
    ::File         - File-based sessions
    ::S3           - S3-based sessions
  ::Telemetry      - Observability
    ::Tracer       - OpenTelemetry tracing
    ::Metrics      - Usage and performance metrics
```

---

## 2. Python-to-Ruby Mapping

| Python Pattern | Ruby Equivalent                           | Rationale                            |
|---|-------------------------------------------|--------------------------------------|
| `__call__` method | `#call` method (callable)                 | Ruby convention for callable objects |
| `@tool` decorator | `tool` DSL method or class macro          | Ruby uses class-level DSL methods    |
| ABC (Abstract Base Class) | Module with `raise NotImplementedError`   | Ruby duck typing + documentation     |
| TypedDict | Hash with documented keys, or Data/Struct | Lightweight, no dependency           |
| dataclass | Data.define (Ruby 4.0+) or Struct         | Immutable value objects              |
| asyncio/async-await | Threads + Fiber scheduler                 | Ruby concurrency model               |
| Generator/yield | Enumerator or block                       | Ruby iteration patterns              |
| Type hints | YARD documentation + RBS/Sorbet optional  | Runtime duck typing                  |
| `**kwargs` | Keyword arguments / `**opts`              | Native Ruby feature                  |
| Context managers | Block with ensure                         | `begin/ensure` pattern               |
| f-strings | String interpolation                      | Native Ruby feature                  |
| logging module | Logger (stdlib)                           | Standard library                     |
| Protocol classes | Duck typing + respond_to?                 | Ruby convention                      |
| Union types | Case/pattern matching                     | Ruby 4.0+ pattern matching           |
| Pydantic BaseModel | Dry::Struct or plain Data                 | Minimal deps preferred               |

---

## 3. Key Design Decisions

### 3.1 Agent as Callable

```ruby
agent = Strands::Agent.new(model: model, tools: [calculator])
result = agent.call("What is 2 + 2?")
# or
result = agent.("What is 2 + 2?")
```

The Agent class implements `#call` making it a callable object, consistent with
Ruby's Proc/Lambda conventions.

### 3.2 Tool Definition DSL

```ruby
# Block-based tool definition
calculator = Strands::Tools.define(:calculator, description: "Performs math") do |input|
  eval(input[:expression]) # simplified
end

# Class-based tool
class Calculator
  include Strands::Tools::DSL

  tool_name "calculator"
  tool_description "Performs arithmetic operations"
  tool_input_schema(
    type: "object",
    properties: {
      expression: { type: "string", description: "Math expression" }
    },
    required: ["expression"]
  )

  def call(input)
    eval(input[:expression])
  end
end
```

### 3.3 Model Provider Interface

```ruby
module Strands
  module Models
    class Base
      def stream(messages:, system: nil, tool_specs: [], **opts)
        raise NotImplementedError, "#{self.class}#stream must be implemented"
      end

      def format_request(messages:, system: nil, tool_specs: [], **opts)
        raise NotImplementedError
      end
    end
  end
end
```

Models use inheritance from a base class rather than module inclusion,
as they share common token-counting logic and configuration.

### 3.4 Hook System

```ruby
class LoggingHooks
  include Strands::Hooks::Provider

  def register_hooks(registry)
    registry.on(Strands::Hooks::Events::BeforeInvocation) { |event| log_start(event) }
    registry.on(Strands::Hooks::Events::AfterInvocation) { |event| log_end(event) }
  end
end
```

Hooks use a registry pattern with typed events. Event classes are simple
Data objects carrying context.

### 3.5 Interventions as Middleware

```ruby
class SafetyGuard < Strands::Interventions::Handler
  def before_tool_call(event)
    if dangerous?(event.tool_name)
      Strands::Interventions::Deny.new(reason: "Tool #{event.tool_name} is blocked")
    else
      Strands::Interventions::Proceed.new
    end
  end
end
```

Interventions follow the Python pattern closely -- handlers override lifecycle
methods and return action objects.

### 3.6 Streaming with Blocks and Enumerators

```ruby
# Block-based streaming
agent.call("Tell me a story") do |event|
  case event
  in { type: :content_delta, text: String => text }
    print text
  in { type: :tool_use, name: String => name }
    puts "\n[Using tool: #{name}]"
  end
end

# Enumerator-based streaming
agent.stream("Tell me a story").each do |event|
  # process events
end
```

### 3.7 Storage Interface

```ruby
module Strands
  module Storage
    class Base
      def read(key) = raise(NotImplementedError)
      def write(key, value, **metadata) = raise(NotImplementedError)
      def delete(key) = raise(NotImplementedError)
      def list(**filters) = raise(NotImplementedError)
    end
  end
end
```

### 3.8 Error Handling

Custom exceptions inherit from a base `Strands::Error`:

```ruby
module Strands
  class Error < StandardError; end
  class ModelThrottledError < Error; end
  class ContextWindowOverflowError < Error; end
  class ModelTimeoutError < Error; end
  class ToolExecutionError < Error; end
  class EventLoopError < Error; end
end
```

### 3.9 Configuration

Convention over configuration with sensible defaults:

```ruby
Strands::Agent.new(
  model: Strands::Models::Bedrock.new(model_id: "anthropic.claude-3-5-sonnet"),
  system_prompt: "You are a helpful assistant",
  tools: [calculator, weather_lookup],
  hooks: [LoggingHooks.new],
  interventions: [SafetyGuard.new],
  max_turns: 10
)
```

### 3.10 Thread Safety

- Agent state protected by Monitor (allows reentrant locking)
- Tool registry uses concurrent-safe data structures
- Each invocation gets its own context object

---

## 4. Directory Layout

```
strands-rb/
  .kiro/
    requirements.md
    design.md
    tasks.md
  lib/
    strands.rb              # Main entry point, requires submodules
    strands/
      version.rb            # Strands::VERSION
      agent/
        agent.rb            # Core Agent class
        result.rb           # AgentResult
        conversation_manager/
          base.rb
          sliding_window.rb
          summarizing.rb
          null.rb
      models/
        base.rb             # Abstract model interface
        bedrock.rb
        openai.rb
        anthropic.rb
        ollama.rb
        gemini.rb
        lite_llm.rb
        llama_cpp.rb
        mistral.rb
        sage_maker.rb
        writer.rb
      tools/
        registry.rb         # Tool registry
        executor.rb         # Sequential/concurrent executors
        dsl.rb              # Tool definition DSL
        tool_provider.rb    # Provider interface
        mcp/
          client.rb         # MCP protocol client
          types.rb
        structured_output.rb
      event_loop/
        cycle.rb            # Main event loop logic
        streaming.rb        # Stream processing
        retry.rb            # Retry with backoff
      types/
        content.rb          # Content block definitions
        streaming.rb        # Stream event types
        exceptions.rb       # Custom exceptions
        tools.rb            # Tool spec types
      hooks/
        events.rb           # Event class definitions
        registry.rb         # Hook registration
        provider.rb         # HookProvider module
      interventions/
        actions.rb          # Proceed, Deny, Guide, Transform, Confirm
        handler.rb          # Base handler class
        registry.rb         # Handler composition
      plugins/
        base.rb             # Plugin interface
        registry.rb         # Plugin management
      handlers/
        callback_handler.rb # Base handler interface
        printing.rb         # PrintingCallbackHandler
        null.rb             # NullCallbackHandler
      memory/
        manager.rb          # Memory manager
        extraction.rb       # Extraction logic
        types.rb            # Memory types
      storage/
        base.rb             # Storage interface
        in_memory.rb        # Hash-based storage
        local_file.rb       # Filesystem storage
        s3.rb               # S3 storage
      session/
        manager.rb          # Session manager interface
        file_manager.rb     # File-based sessions
        s3_manager.rb       # S3-based sessions
      telemetry/
        tracer.rb           # OpenTelemetry tracing
        metrics.rb          # Metrics collection
        config.rb           # Telemetry configuration
  spec/
    spec_helper.rb
    strands/
      agent/
      models/
      tools/
      ...
  Gemfile
  strands.gemspec
  Rakefile
  .rubocop.yml
  .rspec
  LICENSE
  README.md
```

---

## 5. Dependency Strategy

### Runtime (stdlib only)
- `json` - JSON parsing/generation
- `net/http` - HTTP client for API calls
- `logger` - Structured logging
- `securerandom` - UUID generation
- `fileutils` - File operations
- `uri` - URL parsing
- `monitor` - Thread synchronization
- `openssl` - TLS for HTTPS

### Development
- `rspec` (~> 3.13) - Testing framework
- `rubocop` (~> 1.65) - Code linting
- `rake` (~> 13.0) - Task runner
- `webmock` - HTTP request mocking (tests)
- `simplecov` - Code coverage (optional)

### Optional Runtime (provider-specific)
- `aws-sdk-bedrockruntime` - Bedrock provider
- `aws-sdk-s3` - S3 storage/session
- Provider SDKs loaded on demand via `require`
