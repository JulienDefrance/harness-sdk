# Ollama Provider

The Ollama provider connects to a local Ollama instance for model inference. It uses the Ollama chat API with NDJSON streaming. No API keys or cloud credentials are needed.

## Requirements

- Ollama installed and running locally (or on a remote host)
- A model pulled (e.g., `ollama pull llama3`)
- Network access to the Ollama HTTP endpoint

## Configuration

```ruby
model = Strands::Models::Ollama.new(
  model_id: "llama3",
  host: "http://localhost:11434"
)
```

### Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `model_id` | String | (required) | Ollama model name |
| `host` | String | `"http://localhost:11434"` | Ollama server address |
| `**params` | Hash | `{}` | Additional parameters (temperature, top_p, num_predict, etc.) |

## Supported Models

Any model available via Ollama. Common options:

| Model | Name |
|-------|------|
| Llama 3 (8B) | `llama3` |
| Llama 3 (70B) | `llama3:70b` |
| Mistral (7B) | `mistral` |
| Mixtral (8x7B) | `mixtral` |
| Code Llama | `codellama` |
| Phi-3 | `phi3` |
| Gemma 2 | `gemma2` |
| Command R | `command-r` |
| DeepSeek Coder | `deepseek-coder` |

Pull a model before using it:

```bash
ollama pull llama3
ollama pull mistral
```

## Usage Examples

### Basic Usage

```ruby
require "strands"

model = Strands::Models::Ollama.new(model_id: "llama3")

agent = Strands::Agent::Agent.new(
  model: model,
  system_prompt: "You are a helpful coding assistant."
)

result = agent.call("Write a function to compute fibonacci numbers.")
puts result.text
```

### With Custom Parameters

```ruby
model = Strands::Models::Ollama.new(
  model_id: "mistral",
  temperature: 0.8,
  top_p: 0.9,
  num_predict: 2048
)
```

### With Tools

Tool support depends on the model. Models like Llama 3 and Mistral support function calling:

```ruby
model = Strands::Models::Ollama.new(model_id: "llama3")

calculator = Strands.tool("calculator",
  description: "Evaluates a math expression",
  schema: {
    properties: {
      expression: { type: "string", description: "Math expression to evaluate" }
    },
    required: ["expression"]
  }
) { |expression:| eval(expression).to_s }

agent = Strands::Agent::Agent.new(model: model, tools: [calculator])
result = agent.call("What is 42 * 17?")
```

### Remote Ollama Instance

```ruby
model = Strands::Models::Ollama.new(
  model_id: "llama3",
  host: "http://gpu-server.local:11434"
)
```

## API Details

The provider uses the **Chat** endpoint:

```
POST /api/chat
Host: localhost:11434
Content-Type: application/json
```

### Request Format

```json
{
  "model": "llama3",
  "messages": [
    {"role": "system", "content": "You are helpful."},
    {"role": "user", "content": "Hello!"}
  ],
  "stream": true,
  "options": {
    "temperature": 0.7,
    "num_predict": 2048
  }
}
```

### Streaming Format

Responses stream as newline-delimited JSON (NDJSON):

```json
{"model":"llama3","message":{"role":"assistant","content":"Hello"},"done":false}
{"model":"llama3","message":{"role":"assistant","content":"!"},"done":false}
{"model":"llama3","message":{"role":"assistant","content":""},"done":true,"total_duration":1234567890}
```

### Tool Calls

When tool use is supported, the response includes tool call data:

```json
{"model":"llama3","message":{"role":"assistant","content":"","tool_calls":[{"function":{"name":"calculator","arguments":{"expression":"42 * 17"}}}]},"done":true}
```

## Tool Support Notes

Not all Ollama models support tool calling. Models that support tools include:
- `llama3` and variants
- `mistral` and `mixtral`
- `command-r`

Models without tool support will attempt to respond textually to tool-related prompts. For best results with tools, use models that explicitly support function calling.

## Error Handling

| Scenario | Exception | Description |
|----------|-----------|-------------|
| Connection refused | `Errno::ECONNREFUSED` | Ollama not running |
| Context overflow | `ContextWindowOverflowError` | Input exceeds model context |
| Timeout | `Net::ReadTimeout` | Model took too long |

Since Ollama runs locally, rate limiting (429) is not typical. Errors are usually connection issues or context overflow.

## Tips

1. **GPU acceleration**: Ensure Ollama is configured with GPU access for reasonable inference speed.
2. **Context length**: Larger models typically have larger context windows. Check model documentation.
3. **Memory**: Large models (70B+) require significant RAM/VRAM. Monitor system resources.
4. **Keep-alive**: Ollama keeps models in memory by default. Use `ollama stop <model>` to free resources.
