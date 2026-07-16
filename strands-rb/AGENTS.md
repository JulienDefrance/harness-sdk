# AGENTS.md - Guide for AI Coding Agents

This document provides structured guidance for AI coding agents working on the Strands Ruby SDK.

## Repository Layout

```
strands-rb/
  lib/strands/           # All source code, organized by module
  spec/                  # RSpec tests, mirrors lib/ structure
  docs/                  # Documentation (architecture, provider guides)
  strands.gemspec        # Gem specification
  Gemfile                # Development dependencies
  Rakefile               # Build tasks
  .rubocop.yml           # Linter configuration
  CLAUDE.md              # Claude-specific steering
  AGENTS.md              # This file
  README.md              # Project documentation
  LICENSE                # Apache-2.0
```

### Module Organization

Each functional area lives in its own subdirectory under `lib/strands/`:

| Directory | Purpose |
|-----------|---------|
| `agent/` | Core Agent class, Result, ConversationManager |
| `models/` | Model provider interface and implementations |
| `tools/` | Tool registry, execution, DSL, MCP client |
| `event_loop/` | Turn cycle orchestration, retry logic |
| `hooks/` | Event types, registry, provider interface |
| `interventions/` | Handler base, registry, action types |
| `plugins/` | Plugin base module, discovery |
| `handlers/` | Callback handlers (printing, null) |
| `storage/` | Persistence backends |
| `session/` | Session lifecycle management |
| `memory/` | Cross-session fact storage |
| `telemetry/` | Tracing and metrics |
| `types/` | Shared type definitions |

## Development Workflow

### 1. Understand the Change

Before modifying code:
- Read the file you plan to change
- Read tests for that file (if they exist)
- Check `docs/ARCHITECTURE.md` for how the component fits in
- Look at related modules that may be affected

### 2. Make the Change

- Follow all coding conventions listed below
- Keep changes focused on the task
- Do not refactor unrelated code

### 3. Validate

```bash
# Validate syntax of modified files
ruby -c lib/strands/models/openai.rb

# Run relevant tests
bundle exec rspec spec/strands/models/openai_spec.rb

# Run full suite
bundle exec rspec

# Check style
bundle exec rubocop
```

### 4. Commit

- Use conventional commit format: `feat:`, `fix:`, `docs:`, `refactor:`, `chore:`, `test:`
- Keep commits focused (one logical change per commit)
- Include the module name in the message when relevant: `feat(models): add streaming retry`

## Code Style Rules

### Required

1. **`frozen_string_literal: true`** pragma on every `.rb` file (first line)
2. **YARD documentation** on all public methods (`@param`, `@return`, `@raise`, `@example`)
3. **Module nesting** (explicit `module Strands; module X; end; end` not `Strands::X`)
4. **Keyword arguments** preferred over positional for methods with 2+ parameters
5. **`snake_case`** for methods and local variables
6. **`PascalCase`** for classes and modules
7. **`SCREAMING_SNAKE_CASE`** for constants
8. **Predicate methods** end with `?`
9. **Bang methods** end with `!` for destructive operations
10. **Two-space indentation** (no tabs)

### Prohibited

1. **No external runtime gems** - Only Ruby stdlib for production code
2. **No `require_relative`** in lib/ - Use `autoload` in the root module
3. **No monkey-patching** of core classes
4. **No global state** except explicit module-level singletons (e.g., `Telemetry.tracer`)
5. **No interactive/console code** in library files
6. **No `puts`/`print`** except in handler classes designed for output

### Preferred

1. **Guard clauses** over nested conditionals
2. **`return unless`** over `if/end` for early returns
3. **Struct** for simple data containers (see `types/` module)
4. **Frozen collections** for constants (`.freeze`)
5. **`raise ArgumentError`** for validation, `NotImplementedError` for interfaces

## Testing Requirements

### Coverage Expectations

- All public methods must have at least one test
- Error paths must be tested (raises, edge cases)
- Model specs must test streaming, tool use, and error scenarios
- New tools must have execution tests

### Spec Structure

```ruby
# frozen_string_literal: true

require "spec_helper"

RSpec.describe Strands::Module::ClassName do
  # Shared setup
  let(:instance) { described_class.new(...) }

  describe "#method_name" do
    context "when condition is met" do
      it "does the expected thing" do
        # arrange, act, assert
      end
    end

    context "when error occurs" do
      it "raises the appropriate error" do
        expect { instance.method_name }.to raise_error(SomeError)
      end
    end
  end
end
```

### Mocking HTTP

Never make real HTTP requests in tests. Use `instance_double(Net::HTTP)` with the `stub_http_streaming` and `stub_http_error` helpers defined in spec_helper or inline.

### File Naming

- Spec files: `spec/strands/<module>/<class>_spec.rb`
- Must mirror the `lib/` path exactly

## PR Checklist

Before submitting a pull request, verify:

- [ ] All modified Ruby files pass `ruby -c` syntax check
- [ ] All existing tests pass (`bundle exec rspec`)
- [ ] New public methods have YARD documentation
- [ ] New functionality has corresponding tests
- [ ] No external runtime dependencies added
- [ ] `frozen_string_literal: true` on all new files
- [ ] Commit messages use conventional format
- [ ] No unrelated changes included
- [ ] Error cases are handled (not just happy path)

## Common Tasks

### Adding a New Model Provider

1. Create `lib/strands/models/<provider>.rb`
2. Include `Strands::Models::Base` and `Strands::Models::StreamEventBuilder`
3. Implement: `#initialize`, `#stream`, `#update_config`, `#get_config`, `#inspect`
4. Handle errors: 429 -> `ModelThrottledError`, context overflow -> `ContextWindowOverflowError`
5. Create `spec/strands/models/<provider>_spec.rb` following existing patterns
6. Add autoload entry in `lib/strands.rb`
7. Create `docs/providers/<PROVIDER>.md`

### Adding a New Tool

1. Define using DSL or Definition class
2. Ensure schema has `type: "object"`, `properties`, and `required`
3. Callable receives keyword arguments matching schema properties
4. Return a string or hash (will be serialized to tool result)
5. Test with a simple agent invocation

### Adding a New Hook Event

1. Define event class in `lib/strands/hooks/events.rb`
2. Extend `Event` or `AgentEvent`
3. Add `reverse_callbacks?` returning `true` for "after" events
4. Fire the event from the appropriate location using `hook_registry.fire(event)`
5. Document the event in the hooks section of ARCHITECTURE.md

### Adding an Intervention Handler

1. Subclass `Strands::Interventions::Handler`
2. Implement `#name` (must be unique)
3. Override lifecycle methods: `before_invocation`, `before_tool_call`, etc.
4. Return action objects: `Proceed`, `Deny`, `Guide`, or `Transform`
5. Optionally override `#on_error` (`:throw`, `:proceed`, or `:deny`)

### Adding a Storage Backend

1. Create class under `lib/strands/storage/`
2. Include `Strands::Storage::Base`
3. Implement: `#read`, `#write`, `#delete`, `#exists?`, `#list`
4. Use `normalize_key` and `normalize_prefix` helpers from Base
5. Ensure thread safety if the backend may be shared

## Dependency Policy

### Runtime Dependencies

**NONE.** The SDK must function with only the Ruby standard library. This is a hard requirement.

Rationale:
- Minimizes version conflicts in user applications
- Ensures the gem works in constrained environments
- Keeps the dependency tree flat

### Optional Dependencies

These are detected at runtime but never required:
- `aws-sdk-bedrockruntime` - Used by Bedrock provider if available
- Any OpenTelemetry gems - Can be integrated via the Telemetry module

### Development Dependencies

Allowed in Gemfile/gemspec `development_dependencies`:
- `rspec` - Testing framework
- `rubocop` - Linter
- `rake` - Task runner
- `yard` - Documentation generator

## File Naming Conventions

| Type | Convention | Example |
|------|-----------|---------|
| Class file | `snake_case.rb` matching class name | `mcp_client.rb` for `MCPClient` |
| Spec file | `<class>_spec.rb` | `mcp_client_spec.rb` |
| Module file | `snake_case.rb` | `stream_event_builder.rb` |
| Doc file | `SCREAMING_CASE.md` | `ARCHITECTURE.md` |
| Provider doc | `SCREAMING_CASE.md` | `BEDROCK.md` |

## Module Organization Rules

1. One primary class/module per file
2. Small supporting classes can live in the same file (e.g., `ToolCaller` in `agent.rb`)
3. Shared types go in `types/` subdirectory
4. Interfaces (modules meant to be included) live alongside implementations
5. Private helper methods stay in the same file as the public methods they support
6. Constants related to a class live inside that class (e.g., `DEFAULT_HOST`)
