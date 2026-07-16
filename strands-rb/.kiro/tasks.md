# Strands Ruby SDK - Implementation Tasks

## Phase 1: Foundation

### Task 1.1: Project Skeleton (FEAT-001)
- [x] Initialize gem structure (gemspec, Gemfile, Rakefile)
- [x] Configure RuboCop, RSpec
- [x] Create module hierarchy under lib/strands/
- [x] Create .kiro documentation (requirements, design, tasks)
- [x] Add LICENSE and README

### Task 1.2: Type System & Exceptions (FEAT-002)
- [ ] Define content block type helpers (Strands::Types::Content)
- [ ] Define streaming event types (Strands::Types::Streaming)
- [ ] Define tool spec types (Strands::Types::Tools)
- [ ] Define custom exceptions (Strands::Types::Exceptions)
- [ ] Write specs for type validation helpers

### Task 1.3: Hook System (FEAT-003)
- [ ] Implement hook event classes (Data.define based)
- [ ] Implement HookRegistry with callback registration
- [ ] Implement HookProvider module
- [ ] Implement hook ordering (before, normal, after)
- [ ] Write specs for hook dispatch

---

## Phase 2: Core Engine

### Task 2.1: Model Base & Interface (FEAT-004)
- [ ] Implement Strands::Models::Base abstract class
- [ ] Define stream method contract
- [ ] Implement token counting heuristics
- [ ] Implement model configuration (model_id, temperature, etc.)
- [ ] Write specs for base model behavior

### Task 2.2: Tool System (FEAT-005)
- [ ] Implement Strands::Tools::Registry
- [ ] Implement tool definition DSL (block-based and class-based)
- [ ] Implement sequential tool executor
- [ ] Implement concurrent tool executor (thread pool)
- [ ] Implement tool provider interface
- [ ] Write specs for tool registration and execution

### Task 2.3: Event Loop (FEAT-006)
- [ ] Implement event loop cycle (message -> model -> tool -> repeat)
- [ ] Implement streaming event processing
- [ ] Implement retry strategy with exponential backoff
- [ ] Implement error recovery (max_tokens, missing tool results)
- [ ] Write specs for event loop behavior

### Task 2.4: Agent Class (FEAT-007)
- [ ] Implement Strands::Agent with #call interface
- [ ] Wire up model, tools, hooks, interventions
- [ ] Implement conversation history management
- [ ] Implement agent result objects
- [ ] Implement streaming via blocks
- [ ] Implement conversation managers (sliding window, summarizing, null)
- [ ] Write specs for agent invocation

---

## Phase 3: Interventions & Plugins

### Task 3.1: Interventions (FEAT-008)
- [ ] Implement action classes (Proceed, Deny, Guide, Transform, Confirm)
- [ ] Implement InterventionHandler base class
- [ ] Implement InterventionRegistry with composition logic
- [ ] Implement error handling modes (throw, proceed, deny)
- [ ] Write specs for intervention flow

### Task 3.2: Plugins
- [ ] Implement Plugin base interface
- [ ] Implement PluginRegistry
- [ ] Implement auto-discovery of hooks/tools/interventions from plugins
- [ ] Write specs for plugin lifecycle

---

## Phase 4: Persistence & Memory

### Task 4.1: Storage Backends
- [ ] Implement Storage::Base interface
- [ ] Implement Storage::InMemory
- [ ] Implement Storage::LocalFile
- [ ] Implement Storage::S3 (lazy-loaded aws-sdk)
- [ ] Write specs for each backend

### Task 4.2: Session Management
- [ ] Implement Session::Manager interface
- [ ] Implement Session::FileManager
- [ ] Implement Session::S3Manager
- [ ] Implement session lifecycle (create, save, load, delete)
- [ ] Write specs for session CRUD

### Task 4.3: Memory System
- [ ] Implement Memory::Manager
- [ ] Implement extraction coordinator
- [ ] Implement model-based extraction
- [ ] Implement memory storage and retrieval
- [ ] Write specs for memory extraction

---

## Phase 5: Model Providers

### Task 5.1: Bedrock Provider
- [ ] Implement Strands::Models::Bedrock
- [ ] Map Converse API to streaming events
- [ ] Handle tool use formatting
- [ ] Write specs with mocked API responses

### Task 5.2: OpenAI Provider
- [ ] Implement Strands::Models::OpenAI
- [ ] Map Chat Completions API to streaming events
- [ ] Handle function calling format
- [ ] Write specs with mocked API responses

### Task 5.3: Anthropic Provider
- [ ] Implement Strands::Models::Anthropic
- [ ] Map Messages API to streaming events
- [ ] Handle tool use blocks
- [ ] Write specs with mocked API responses

### Task 5.4: Other Providers
- [ ] Implement Ollama provider
- [ ] Implement Gemini provider
- [ ] Implement LiteLLM provider
- [ ] Implement LlamaCpp provider
- [ ] Implement Mistral provider
- [ ] Implement SageMaker provider
- [ ] Implement Writer provider

---

## Phase 6: Observability & Polish

### Task 6.1: Telemetry
- [ ] Implement Tracer (OpenTelemetry span creation)
- [ ] Implement Metrics collection
- [ ] Implement telemetry configuration
- [ ] Write specs for span attributes

### Task 6.2: Handlers (Legacy Callbacks)
- [ ] Implement CallbackHandler interface
- [ ] Implement PrintingCallbackHandler
- [ ] Implement NullCallbackHandler
- [ ] Write specs for handler dispatch

### Task 6.3: MCP Client
- [ ] Implement MCP stdio transport
- [ ] Implement MCP SSE transport
- [ ] Implement tool discovery from MCP servers
- [ ] Implement tool invocation via MCP
- [ ] Write specs with mocked MCP server

---

## Phase 7: Integration & Documentation

### Task 7.1: Integration Tests
- [ ] End-to-end agent invocation with mock model
- [ ] Multi-turn conversation tests
- [ ] Tool execution round-trip tests
- [ ] Intervention flow tests
- [ ] Streaming tests

### Task 7.2: Documentation
- [ ] YARD docs on all public APIs
- [ ] Usage examples in README
- [ ] Architecture guide
- [ ] Provider setup guides

---

## Implementation Notes

- Each task should be independently testable
- Phases can overlap where dependencies allow
- Provider implementations (Phase 5) can proceed in parallel
- All specs must pass before moving to next phase
- Maintain backward compatibility within 0.x releases
