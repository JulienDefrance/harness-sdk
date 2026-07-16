# Strands Ruby SDK - Implementation Tasks

## Phase 1: Foundation

### Task 1.1: Project Skeleton (FEAT-001)
- [x] Initialize gem structure (gemspec, Gemfile, Rakefile)
- [x] Configure RuboCop, RSpec
- [x] Create module hierarchy under lib/strands/
- [x] Create .kiro documentation (requirements, design, tasks)
- [x] Add LICENSE and README

### Task 1.2: Type System & Exceptions (FEAT-002)
- [x] Define content block type helpers (Strands::Types::Content)
- [x] Define streaming event types (Strands::Types::Streaming)
- [x] Define tool spec types (Strands::Types::Tools)
- [x] Define custom exceptions (Strands::Types::Exceptions)
- [x] Write specs for type validation helpers

### Task 1.3: Hook System (FEAT-003)
- [x] Implement hook event classes (Data.define based)
- [x] Implement HookRegistry with callback registration
- [x] Implement HookProvider module
- [x] Implement hook ordering (before, normal, after)
- [x] Write specs for hook dispatch

---

## Phase 2: Core Engine

### Task 2.1: Model Base & Interface (FEAT-004)
- [x] Implement Strands::Models::Base abstract class
- [x] Define stream method contract
- [x] Implement token counting heuristics
- [x] Implement model configuration (model_id, temperature, etc.)
- [x] Write specs for base model behavior

### Task 2.2: Tool System (FEAT-005)
- [x] Implement Strands::Tools::Registry
- [x] Implement tool definition DSL (block-based and class-based)
- [x] Implement sequential tool executor
- [x] Implement concurrent tool executor (thread pool)
- [x] Implement tool provider interface
- [x] Write specs for tool registration and execution

### Task 2.3: Event Loop (FEAT-006)
- [x] Implement event loop cycle (message -> model -> tool -> repeat)
- [x] Implement streaming event processing
- [x] Implement retry strategy with exponential backoff
- [x] Implement error recovery (max_tokens, missing tool results)
- [x] Write specs for event loop behavior

### Task 2.4: Agent Class (FEAT-007)
- [x] Implement Strands::Agent with #call interface
- [x] Wire up model, tools, hooks, interventions
- [x] Implement conversation history management
- [x] Implement agent result objects
- [x] Implement streaming via blocks
- [x] Implement conversation managers (sliding window, summarizing, null)
- [x] Write specs for agent invocation

---

## Phase 3: Interventions & Plugins

### Task 3.1: Interventions (FEAT-008)
- [x] Implement action classes (Proceed, Deny, Guide, Transform, Confirm)
- [x] Implement InterventionHandler base class
- [x] Implement InterventionRegistry with composition logic
- [x] Implement error handling modes (throw, proceed, deny)
- [x] Write specs for intervention flow

### Task 3.2: Plugins
- [x] Implement Plugin base interface
- [x] Implement PluginRegistry
- [x] Implement auto-discovery of hooks/tools/interventions from plugins
- [x] Write specs for plugin lifecycle

---

## Phase 4: Persistence & Memory

### Task 4.1: Storage Backends
- [x] Implement Storage::Base interface
- [x] Implement Storage::InMemory
- [x] Implement Storage::LocalFile
- [ ] Implement Storage::S3 (lazy-loaded aws-sdk)
- [x] Write specs for each backend

### Task 4.2: Session Management
- [x] Implement Session::Manager interface
- [x] Implement Session::FileManager
- [ ] Implement Session::S3Manager
- [x] Implement session lifecycle (create, save, load, delete)
- [x] Write specs for session CRUD

### Task 4.3: Memory System
- [x] Implement Memory::Manager
- [x] Implement extraction coordinator
- [x] Implement model-based extraction
- [x] Implement memory storage and retrieval
- [x] Write specs for memory extraction

---

## Phase 5: Model Providers

### Task 5.1: Bedrock Provider
- [x] Implement Strands::Models::Bedrock
- [x] Map Converse API to streaming events
- [x] Handle tool use formatting
- [x] Write specs with mocked API responses

### Task 5.2: OpenAI Provider
- [x] Implement Strands::Models::OpenAI
- [x] Map Chat Completions API to streaming events
- [x] Handle function calling format
- [x] Write specs with mocked API responses

### Task 5.3: Anthropic Provider
- [x] Implement Strands::Models::Anthropic
- [x] Map Messages API to streaming events
- [x] Handle tool use blocks
- [x] Write specs with mocked API responses

### Task 5.4: Other Providers
- [x] Implement Ollama provider
- [ ] Implement Gemini provider
- [ ] Implement LiteLLM provider
- [ ] Implement LlamaCpp provider
- [ ] Implement Mistral provider
- [ ] Implement SageMaker provider
- [ ] Implement Writer provider

---

## Phase 6: Observability & Polish

### Task 6.1: Telemetry
- [x] Implement Tracer (OpenTelemetry span creation)
- [x] Implement Metrics collection
- [x] Implement telemetry configuration
- [x] Write specs for span attributes

### Task 6.2: Handlers (Legacy Callbacks)
- [x] Implement CallbackHandler interface
- [x] Implement PrintingCallbackHandler
- [x] Implement NullCallbackHandler
- [x] Write specs for handler dispatch

### Task 6.3: MCP Client
- [x] Implement MCP stdio transport
- [x] Implement MCP SSE transport
- [x] Implement tool discovery from MCP servers
- [x] Implement tool invocation via MCP
- [x] Write specs with mocked MCP server

---

## Phase 7: Integration & Documentation

### Task 7.1: Integration Tests
- [x] End-to-end agent invocation with mock model
- [x] Multi-turn conversation tests
- [x] Tool execution round-trip tests
- [x] Intervention flow tests
- [x] Streaming tests

### Task 7.2: Documentation
- [x] YARD docs on all public APIs
- [x] Usage examples in README
- [x] Architecture guide
- [x] Provider setup guides

---

## Implementation Notes

- Each task should be independently testable
- Phases can overlap where dependencies allow
- Provider implementations (Phase 5) can proceed in parallel
- All specs must pass before moving to next phase
- Maintain backward compatibility within 0.x releases
