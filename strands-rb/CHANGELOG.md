# Changelog

All notable changes to the Strands Ruby SDK will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- `Strands::Agent::Agent.new` now defaults to `Strands::Models::Bedrock` when no
  `model` is given, matching the Python and TypeScript SDKs.
- `Strands::Models::Bedrock.new` now defaults `model_id` to
  `Bedrock::DEFAULT_BEDROCK_MODEL_ID` (currently `"global.anthropic.claude-sonnet-4-6"`)
  when not provided, emitting a warning on `$stderr` since the default is subject to
  change between releases.

## [0.1.0] - 2025-07-16

### Added

- Initial release of the Strands Ruby SDK.
- `Strands::Agent` for building composable AI agents with an event loop
  driven execution model.
- Model providers: Bedrock, OpenAI, Anthropic, and Ollama.
- Tool support, including a DSL for defining tools and an MCP (Model Context
  Protocol) client for integrating external tool servers.
- Hooks system for observing and extending agent lifecycle events.
- Interventions for pausing, approving, or modifying agent behavior at
  runtime.
- Plugin system for discovering and loading extensions.
- Storage backends (in-memory and local file) and a session manager built on
  top of them.
- Conversation memory management.
- Telemetry primitives (metrics and tracing) with no external dependencies.
- No runtime dependencies; the gem relies solely on the Ruby standard
  library.

[Unreleased]: https://github.com/strands-agents/strands-rb/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/strands-agents/strands-rb/releases/tag/v0.1.0
