# OpenAI Provider

The OpenAI provider connects to the OpenAI Chat Completions API using Server-Sent Events (SSE) for streaming responses. It works with the official OpenAI API and any compatible endpoint (Azure OpenAI, Anyscale, vLLM, etc.).

## Requirements

- OpenAI API key (or compatible endpoint credentials)
- Network access to the API endpoint

## Configuration

```ruby
model = Strands::Models::OpenAI.new(
  model_id: "gpt-4o",
  api_key: "sk-...",
  base_url: "https://api.openai.com"
)
```

### Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `model_id` | String | (required) | Model identifier |
| `api_key` | String | `ENV["OPENAI_API_KEY"]` | API key for authentication |
| `base_url` | String | `"https://api.openai.com"` | API base URL |
| `**params` | Hash | `{}` | Additional model parameters (temperature, max_tokens, etc.) |

### Environment Variables

- `OPENAI_API_KEY` - API key (used when `api_key` not passed explicitly)

## Supported Model IDs

| Model | ID |
|-------|-----|
| GPT-4o | `gpt-4o` |
| GPT-4o Mini | `gpt-4o-mini` |
| GPT-4 Turbo | `gpt-4-turbo` |
| GPT-4 | `gpt-4` |
| GPT-3.5 Turbo | `gpt-3.5-turbo` |
| o1 | `o1` |
| o1-mini | `o1-mini` |

## Usage Examples

### Basic Usage

```ruby
require "strands"

model = Strands::Models::OpenAI.new(model_id: "gpt-4o")

agent = Strands::Agent::Agent.new(
  model: model,
  system_prompt: "You are a helpful assistant."
)

result = agent.call("Explain quantum computing in simple terms.")
puts result.text
```

### With Custom Parameters

```ruby
model = Strands::Models::OpenAI.new(
  model_id: "gpt-4o",
  temperature: 0.3,
  max_tokens: 1024,
  top_p: 0.95
)
```

### With Tools

```ruby
model = Strands::Models::OpenAI.new(model_id: "gpt-4o")

weather = Strands.tool("get_weather",
  description: "Get current weather for a city",
  schema: {
    properties: {
      city: { type: "string", description: "City name" }
    },
    required: ["city"]
  }
) { |city:| "Sunny, 72F in #{city}" }

agent = Strands::Agent::Agent.new(model: model, tools: [weather])
result = agent.call("What's the weather in San Francisco?")
```

### Using Compatible Endpoints

The provider works with any OpenAI-compatible API:

```ruby
# Azure OpenAI
model = Strands::Models::OpenAI.new(
  model_id: "gpt-4o",
  base_url: "https://your-resource.openai.azure.com/openai/deployments/your-deployment",
  api_key: ENV["AZURE_OPENAI_API_KEY"]
)

# Local vLLM
model = Strands::Models::OpenAI.new(
  model_id: "meta-llama/Llama-3-8b-chat-hf",
  base_url: "http://localhost:8000",
  api_key: "dummy"  # vLLM doesn't require a real key
)

# Anyscale
model = Strands::Models::OpenAI.new(
  model_id: "meta-llama/Llama-3-70b-chat-hf",
  base_url: "https://api.endpoints.anyscale.com/v1",
  api_key: ENV["ANYSCALE_API_KEY"]
)
```

## API Details

The provider uses the **Chat Completions** endpoint:

```
POST /v1/chat/completions
Host: api.openai.com
Authorization: Bearer sk-...
Content-Type: application/json
```

### Streaming Format

Responses stream via Server-Sent Events (SSE):

```
data: {"id":"chatcmpl-...","object":"chat.completion.chunk","choices":[{"delta":{"role":"assistant"},"index":0}]}

data: {"id":"chatcmpl-...","object":"chat.completion.chunk","choices":[{"delta":{"content":"Hello"},"index":0}]}

data: {"id":"chatcmpl-...","object":"chat.completion.chunk","choices":[{"delta":{},"finish_reason":"stop","index":0}]}

data: [DONE]
```

### Tool Calls

When the model decides to use a tool, the streaming response includes tool call deltas:

```
data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_abc","type":"function","function":{"name":"get_weather","arguments":""}}]}}]}

data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\"city\":"}}]}}]}

data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\"SF\"}"}}]}}]}
```

## Error Handling

| HTTP Status | Exception | Description |
|-------------|-----------|-------------|
| 429 | `ModelThrottledError` | Rate limited; retry with backoff |
| 400 (context overflow) | `ContextWindowOverflowError` | Input exceeds context window |
| Other 4xx/5xx | `ModelError` | General model error |

The event loop handles 429 errors with automatic exponential backoff retry.
