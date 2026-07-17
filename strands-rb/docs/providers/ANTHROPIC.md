# Anthropic Provider

The Anthropic provider connects to the Anthropic Messages API using Server-Sent Events (SSE) for streaming responses. It supports Claude model family with tool use.

## Requirements

- Anthropic API key
- Network access to the Anthropic API endpoint

## Configuration

```ruby
model = Strands::Models::Anthropic.new(
  model_id: "claude-3-5-sonnet-20241022",
  max_tokens: 4096,
  api_key: "sk-ant-..."
)
```

### Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `model_id` | String | (required) | Claude model identifier |
| `max_tokens` | Integer | `4096` | Maximum tokens to generate |
| `api_key` | String | `ENV["ANTHROPIC_API_KEY"]` | API key |
| `base_url` | String | `"https://api.anthropic.com"` | API base URL |
| `**params` | Hash | `{}` | Additional parameters (temperature, top_p, etc.) |

### Environment Variables

- `ANTHROPIC_API_KEY` - API key (used when `api_key` not passed explicitly)

## Supported Model IDs

| Model | ID |
|-------|-----|
| Claude 3.5 Sonnet | `claude-3-5-sonnet-20241022` |
| Claude 3.5 Haiku | `claude-3-5-haiku-20241022` |
| Claude 3 Opus | `claude-3-opus-20240229` |
| Claude 3 Sonnet | `claude-3-sonnet-20240229` |
| Claude 3 Haiku | `claude-3-haiku-20240307` |

## Usage Examples

### Basic Usage

```ruby
require "strands"

model = Strands::Models::Anthropic.new(
  model_id: "claude-3-5-sonnet-20241022",
  max_tokens: 4096
)

agent = Strands::Agent::Agent.new(
  model: model,
  system_prompt: "You are a helpful coding assistant."
)

result = agent.call("Write a Ruby method to reverse a linked list.")
puts result.text
```

### With Custom Parameters

```ruby
model = Strands::Models::Anthropic.new(
  model_id: "claude-3-5-sonnet-20241022",
  max_tokens: 8192,
  temperature: 0.5,
  top_p: 0.9
)
```

### With Tools

```ruby
model = Strands::Models::Anthropic.new(
  model_id: "claude-3-5-sonnet-20241022"
)

file_reader = Strands.tool("read_file",
  description: "Read the contents of a file",
  schema: {
    properties: {
      path: { type: "string", description: "File path to read" }
    },
    required: ["path"]
  }
) { |path:| File.read(path) }

agent = Strands::Agent::Agent.new(model: model, tools: [file_reader])
result = agent.call("Read and summarize the contents of config.yml")
```

### Custom Base URL

For Anthropic-compatible proxies or self-hosted endpoints:

```ruby
model = Strands::Models::Anthropic.new(
  model_id: "claude-3-5-sonnet-20241022",
  base_url: "https://my-proxy.example.com"
)
```

## API Details

The provider uses the **Messages** endpoint:

```
POST /v1/messages
Host: api.anthropic.com
x-api-key: sk-ant-...
anthropic-version: 2023-06-01
Content-Type: application/json
```

### Request Format

```json
{
  "model": "claude-3-5-sonnet-20241022",
  "max_tokens": 4096,
  "system": "You are a helpful assistant.",
  "messages": [
    {"role": "user", "content": "Hello!"}
  ],
  "stream": true
}
```

### Streaming Format

Responses stream via Server-Sent Events (SSE):

```
event: message_start
data: {"type":"message_start","message":{"id":"msg_...","role":"assistant",...}}

event: content_block_start
data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}

event: content_block_stop
data: {"type":"content_block_stop","index":0}

event: message_delta
data: {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":5}}

event: message_stop
data: {"type":"message_stop"}
```

### Tool Use

When the model decides to use a tool:

```
event: content_block_start
data: {"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"toolu_...","name":"read_file","input":{}}}

event: content_block_delta
data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\"path\":"}}

event: content_block_delta
data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"\"config.yml\"}"}}

event: content_block_stop
data: {"type":"content_block_stop","index":1}
```

### Tool Choice

The provider supports multiple tool selection strategies:

```ruby
# Auto (model decides)
agent = Strands::Agent::Agent.new(model: model, tools: tools)

# Force a specific tool (via model config)
model.update_config(tool_choice: Strands::Types::Tools::ToolChoiceTool.new(name: "read_file"))

# Require any tool
model.update_config(tool_choice: Strands::Types::Tools::ToolChoiceAny.new)
```

## Error Handling

| HTTP Status | Exception | Description |
|-------------|-----------|-------------|
| 429 | `ModelThrottledError` | Rate limited; retry with backoff |
| 529 | `ModelThrottledError` | API overloaded; retry with backoff |
| 400 (overflow) | `ContextWindowOverflowError` | Input exceeds context window |
| Other 4xx/5xx | `ModelError` | General model error |

Both 429 (rate limit) and 529 (overloaded) are treated as transient errors and retried automatically by the event loop.
