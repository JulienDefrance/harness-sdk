# Strands Ruby SDK - Requirements

## Overview

The Strands Ruby SDK provides a framework for building, deploying, and managing AI agents in Ruby.
It aims for feature parity with the Python Strands SDK while following Ruby idioms and conventions.

**Target Ruby Version:** 4.0.6

---

## 1. Core Agent System

### REQ-AGENT-001: Agent Class
- Agent is the primary entry point for interacting with foundation models and tools
- Agent supports natural language invocation: `agent.call("Analyze this data")`
- Agent supports method-style tool access: `agent.tool.tool_name(param1: "value")`
- Agent maintains conversation history (messages array)
- Agent is configurable with system prompt, model, tools, hooks, and interventions

### REQ-AGENT-002: Agent Lifecycle
- Agent fires lifecycle events: initialized, before_invocation, after_invocation
- Agent supports streaming responses via blocks/enumerators
- Agent tracks state (idle, running, completed, errored)
- Agent provides result objects with message content, stop reason, and metrics

### REQ-AGENT-003: Conversation Management
- Support sliding window conversation management (message count limits)
- Support summarizing conversation management (compress old messages)
- Support null conversation manager (no management, keep all)
- Configurable window size and compression strategies

### REQ-AGENT-004: Agent as Tool
- An agent can be wrapped as a tool for use by another agent
- Enables multi-agent orchestration patterns

### REQ-AGENT-005: Concurrency
- Support concurrent tool execution (thread pool)
- Support sequential tool execution (default)
- Configurable executor strategy

---

## 2. Model Providers

### REQ-MODEL-001: Model Base Interface
- Abstract base class/module defining the model provider contract
- Models must implement `stream(messages:, system:, tool_specs:)` method
- Models yield streaming events (content deltas, tool use, metadata)
- Models report token usage (input_tokens, output_tokens)

### REQ-MODEL-002: Provider Implementations
- Amazon Bedrock (Converse API)
- OpenAI (Chat Completions API)
- Anthropic (Messages API)
- Ollama (local models)
- Gemini (Google AI)
- LiteLLM (multi-provider proxy)
- LlamaCpp (local GGUF models)
- Mistral
- SageMaker
- Writer

### REQ-MODEL-003: Model Configuration
- Configurable model ID, temperature, max tokens, top_p, stop sequences
- Support for model-specific parameters via extra kwargs
- Tool choice configuration: auto, any, specific tool, none

### REQ-MODEL-004: Token Counting
- Heuristic token estimation (characters/4 for text, characters/2 for JSON)
- Provider-specific token counting where available
- Track usage across conversation turns

---

## 3. Tool System

### REQ-TOOL-001: Tool Definition
- Tools defined via DSL (method-level declaration with schema)
- Tools have name, description, and JSON Schema input specification
- Tools receive structured input and return content blocks or strings

### REQ-TOOL-002: Tool Registry
- Central registry managing available tools
- Support adding/removing tools dynamically
- Tools can be loaded from multiple sources (direct, MCP, provider)

### REQ-TOOL-003: Tool Execution
- Sequential executor (default, tools run one at a time)
- Concurrent executor (thread pool for parallel tool execution)
- Tool results returned as content blocks (text, images, JSON)

### REQ-TOOL-004: Tool Providers
- Interface for objects that supply tools to an agent
- MCP (Model Context Protocol) client as a tool provider
- Support for tool provider lifecycle (connect, disconnect)

### REQ-TOOL-005: MCP Client
- Connect to MCP servers via stdio or SSE transport
- Discover and invoke tools from MCP servers
- Handle MCP protocol lifecycle

### REQ-TOOL-006: Structured Output
- Support for structured output via tool-based extraction
- JSON Schema validation of tool outputs
- Pydantic-style model mapping (using Ruby equivalents)

### REQ-TOOL-007: Tool Decorator/DSL
- Ruby-idiomatic tool definition (blocks, method annotations, or class-based)
- Automatic JSON Schema generation from method signatures
- Support for required/optional parameters with types and descriptions

---

## 4. Event Loop

### REQ-LOOP-001: Event Loop Cycle
- Orchestrates the agent turn: send messages, process response, handle tool calls
- Iterates until model produces a final response (no more tool calls)
- Respects max_turns/max_tokens limits

### REQ-LOOP-002: Streaming
- Stream model responses as they arrive
- Yield content deltas, tool use events, and metadata events
- Support callback-based and enumerator-based streaming

### REQ-LOOP-003: Retry Logic
- Configurable retry strategy for transient model errors
- Exponential backoff with jitter
- Max attempts, initial delay, max delay configuration

### REQ-LOOP-004: Error Recovery
- Recover from max_tokens reached (split response and continue)
- Generate missing tool results if model expects them
- Handle tool execution failures gracefully

---

## 5. Type System

### REQ-TYPE-001: Content Blocks
- Text blocks: `{ text: "..." }`
- Tool use blocks: `{ tool_use: { tool_use_id:, name:, input: } }`
- Tool result blocks: `{ tool_result: { tool_use_id:, content:, status: } }`
- Image blocks: `{ image: { format:, source: } }`
- Document blocks: `{ document: { format:, name:, source: } }`

### REQ-TYPE-002: Messages
- Messages are arrays of `{ role:, content: }` hashes
- Roles: "user", "assistant"
- Content is an array of content blocks

### REQ-TYPE-003: Tool Specifications
- Tool specs define name, description, and input_schema (JSON Schema)
- Tool choice: auto, any, tool (specific), none

### REQ-TYPE-004: Streaming Events
- Content delta events
- Tool use start/delta/stop events
- Metadata events (usage, stop reason, metrics)
- Debug/trace events

### REQ-TYPE-005: Exceptions
- ModelThrottledException - rate limit hit
- ContextWindowOverflowException - context too large
- ModelTimeoutException - request timed out
- ToolExecutionException - tool failed
- EventLoopException - generic loop error

---

## 6. Hooks System

### REQ-HOOK-001: Hook Events
- AgentInitializedEvent - agent created and configured
- BeforeInvocationEvent - before processing a user message
- AfterInvocationEvent - after completing a response
- BeforeModelCallEvent - before calling the model
- AfterModelCallEvent - after model returns
- BeforeToolCallEvent - before executing a tool
- AfterToolCallEvent - after tool execution completes
- MessageAddedEvent - when a message is added to conversation

### REQ-HOOK-002: Hook Registry
- Register callbacks for specific event types
- Support multiple callbacks per event
- Callbacks receive the event object with context

### REQ-HOOK-003: Hook Providers
- Interface for objects that register hooks
- Providers implement `register_hooks(registry)` method
- Composable: multiple providers can be attached to an agent

### REQ-HOOK-004: Hook Ordering
- Support hook execution order (before, normal, after)
- Deterministic execution within same order level

---

## 7. Interventions

### REQ-INTERV-001: Intervention Actions
- Proceed - allow the operation to continue unchanged
- Deny - block the operation with a reason (fed back to model)
- Guide - modify the request before it continues
- Transform - modify the response after it returns
- Confirm - pause for human approval (human-in-the-loop)

### REQ-INTERV-002: Intervention Handlers
- Base class with lifecycle methods (before_invocation, before_tool_call, etc.)
- Handlers override only the methods they care about
- Default implementation returns Proceed

### REQ-INTERV-003: Intervention Registry
- Manage multiple handlers with priority ordering
- Compose decisions across handlers (first non-Proceed wins)
- Error handling modes: throw, proceed, deny

---

## 8. Plugins

### REQ-PLUGIN-001: Plugin Interface
- Plugins can provide hooks, tools, and interventions
- Plugins implement a registration interface
- Support auto-discovery of plugin capabilities

### REQ-PLUGIN-002: Plugin Registration
- Plugins registered at agent creation or dynamically
- Plugin registry manages lifecycle
- Plugins can declare dependencies

---

## 9. Handlers (Callbacks)

### REQ-HANDLER-001: Callback Handler Interface
- Legacy callback interface for streaming output
- PrintingCallbackHandler - prints to stdout
- NullCallbackHandler - discards all output

### REQ-HANDLER-002: Handler Events
- on_stream_chunk(chunk) - content streaming
- on_tool_start(name, input) - tool execution beginning
- on_tool_end(name, result) - tool execution complete
- on_complete(result) - agent finished

---

## 10. Memory

### REQ-MEMORY-001: Memory Manager
- Cross-session memory recall
- Extract key facts/decisions from conversations
- Store memories with metadata (timestamp, relevance)

### REQ-MEMORY-002: Memory Extraction
- Model-based extraction of important information
- Configurable extraction triggers (turn count, explicit)
- Extraction coordinator managing the process

### REQ-MEMORY-003: Memory Storage
- Persist memories to configured storage backend
- Query memories by relevance/recency
- Memory lifecycle (creation, update, expiration)

---

## 11. Storage

### REQ-STORAGE-001: Storage Interface
- Abstract interface for persisting agent state
- Methods: read, write, delete, list
- Key-value semantics with optional metadata

### REQ-STORAGE-002: Storage Implementations
- InMemoryStorage - hash-based, non-persistent (testing/development)
- LocalFileStorage - filesystem-based persistence
- S3Storage - AWS S3-based persistence

---

## 12. Session Management

### REQ-SESSION-001: Session Manager Interface
- Create, load, save, and delete sessions
- Sessions contain conversation history and metadata
- Support session listing and querying

### REQ-SESSION-002: Session Implementations
- FileSessionManager - local filesystem sessions
- S3SessionManager - S3-backed sessions
- RepositorySessionManager - using storage repositories

### REQ-SESSION-003: Session Lifecycle
- Automatic session save on agent completion
- Session restore on agent initialization
- Session metadata (created_at, updated_at, agent_id)

---

## 13. Telemetry

### REQ-TELEM-001: OpenTelemetry Integration
- Trace spans for agent invocations, model calls, tool calls
- Configurable tracer provider
- Span attributes: model_id, tool_name, token_usage

### REQ-TELEM-002: Metrics
- Event loop metrics (turns, duration, token usage)
- Model call metrics (latency, tokens, errors)
- Tool execution metrics (duration, success/failure)

---

## 14. Non-Functional Requirements

### REQ-NFR-001: Dependencies
- Minimal runtime dependencies (prefer Ruby stdlib)
- Core: json, net/http, logger, securerandom, fileutils, uri (all stdlib)
- Dev only: rspec, rubocop, rake

### REQ-NFR-002: Ruby Version
- Target Ruby 4.0.6
- Use modern Ruby features (pattern matching, Data classes, Fiber scheduler)

### REQ-NFR-003: Testing
- RSpec for all tests
- Unit tests for each module
- Integration tests for agent workflows
- Mock/stub external APIs

### REQ-NFR-004: Code Quality
- RuboCop enforcement (120 char line length)
- YARD documentation on public APIs
- Consistent module/class naming (Strands:: namespace)

### REQ-NFR-005: Thread Safety
- Agent state mutations must be thread-safe
- Tool registry access must be thread-safe
- Use Monitor/Mutex where needed

### REQ-NFR-006: Performance
- Lazy loading of optional components
- Streaming by default (no buffering full responses)
- Efficient memory usage for long conversations
