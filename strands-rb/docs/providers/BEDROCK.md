# AWS Bedrock Provider

The Bedrock provider connects to the AWS Bedrock Converse Stream API for model inference. It uses AWS Signature V4 authentication and requires no external gems (though the optional `aws-sdk-bedrockruntime` gem can be used for SDK-managed auth).

## Requirements

- AWS account with Bedrock model access enabled
- AWS credentials (access key, secret key, and optionally session token)
- The target model must be enabled in your AWS account/region

## Configuration

```ruby
model = Strands::Models::Bedrock.new(
  model_id: "anthropic.claude-3-5-sonnet-20241022-v2:0",
  region: "us-west-2",
  access_key_id: "AKIA...",
  secret_access_key: "wJal...",
  session_token: nil  # optional, for temporary credentials
)
```

### Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `model_id` | String | `Bedrock::DEFAULT_BEDROCK_MODEL_ID` (with a warning) | Bedrock model identifier. Pass explicitly to pin behavior across releases. |
| `region` | String | `ENV["AWS_REGION"]` or `"us-west-2"` | AWS region |
| `access_key_id` | String | `ENV["AWS_ACCESS_KEY_ID"]` | AWS access key ID |
| `secret_access_key` | String | `ENV["AWS_SECRET_ACCESS_KEY"]` | AWS secret access key |
| `session_token` | String | `ENV["AWS_SESSION_TOKEN"]` | AWS session token (temporary creds) |
| `**params` | Hash | `{}` | Additional model parameters (temperature, max_tokens, etc.) |

### Environment Variables

The provider reads credentials from environment variables when not passed explicitly:

- `AWS_REGION` or `AWS_DEFAULT_REGION` - AWS region
- `AWS_ACCESS_KEY_ID` - Access key
- `AWS_SECRET_ACCESS_KEY` - Secret key
- `AWS_SESSION_TOKEN` - Session token (for STS/assumed roles)

## Supported Model IDs

| Model | ID |
|-------|-----|
| Claude 3.5 Sonnet v2 | `anthropic.claude-3-5-sonnet-20241022-v2:0` |
| Claude 3.5 Haiku | `anthropic.claude-3-5-haiku-20241022-v1:0` |
| Claude 3 Opus | `anthropic.claude-3-opus-20240229-v1:0` |
| Claude 3 Sonnet | `anthropic.claude-3-sonnet-20240229-v1:0` |
| Claude 3 Haiku | `anthropic.claude-3-haiku-20240307-v1:0` |
| Llama 3.1 70B | `meta.llama3-1-70b-instruct-v1:0` |
| Llama 3.1 8B | `meta.llama3-1-8b-instruct-v1:0` |
| Mistral Large | `mistral.mistral-large-2407-v1:0` |

## Usage Examples

### Basic Usage

```ruby
require "strands"

model = Strands::Models::Bedrock.new(
  model_id: "anthropic.claude-3-5-sonnet-20241022-v2:0"
)

agent = Strands::Agent::Agent.new(
  model: model,
  system_prompt: "You are a helpful assistant."
)

result = agent.call("What is the capital of France?")
puts result.text
```

### Using the Default Model

If you don't pass a `model` to `Agent.new`, or don't pass a `model_id` to `Bedrock.new`, the
provider falls back to `Bedrock::DEFAULT_BEDROCK_MODEL_ID` and emits a warning on `$stderr`. This
default is subject to change between releases -- pin an explicit `model_id` for stable behavior.

```ruby
require "strands"

# Defaults to Strands::Models::Bedrock with its default model_id.
agent = Strands::Agent::Agent.new(system_prompt: "You are a helpful assistant.")
result = agent.call("What is the capital of France?")
puts result.text
```

### With Additional Parameters

```ruby
model = Strands::Models::Bedrock.new(
  model_id: "anthropic.claude-3-5-sonnet-20241022-v2:0",
  region: "us-east-1",
  temperature: 0.7,
  max_tokens: 2048,
  top_p: 0.9
)
```

### With Tools

```ruby
model = Strands::Models::Bedrock.new(
  model_id: "anthropic.claude-3-5-sonnet-20241022-v2:0"
)

calculator = Strands.tool("calculator",
  description: "Evaluates a math expression",
  schema: {
    properties: { expression: { type: "string" } },
    required: ["expression"]
  }
) { |expression:| eval(expression).to_s }

agent = Strands::Agent::Agent.new(model: model, tools: [calculator])
result = agent.call("What is 123 * 456?")
```

### Using the AWS SDK (Optional)

If the `aws-sdk-bedrockruntime` gem is installed, the provider will automatically detect and use it. This handles credential resolution (instance profiles, SSO, credential files) and request signing.

```ruby
# Gemfile
gem "aws-sdk-bedrockruntime"

# Usage is the same - SDK is detected automatically
model = Strands::Models::Bedrock.new(
  model_id: "anthropic.claude-3-5-sonnet-20241022-v2:0"
)
```

## API Details

The provider uses the **Converse Stream** API endpoint:

```
POST /model/{modelId}/converse-stream
Host: bedrock-runtime.{region}.amazonaws.com
```

### Authentication

Without the AWS SDK gem, the provider performs manual AWS Signature V4 signing using Ruby's `openssl` stdlib. Credentials are read from constructor arguments or environment variables.

With the SDK gem, credential resolution follows the standard AWS SDK chain (environment, shared credentials file, instance profiles, etc.).

### Streaming Format

Bedrock streams binary-encoded JSON events:

```json
{"messageStart": {"role": "assistant"}}
{"contentBlockStart": {"contentBlockIndex": 0, "start": {}}}
{"contentBlockDelta": {"contentBlockIndex": 0, "delta": {"text": "Hello"}}}
{"contentBlockStop": {"contentBlockIndex": 0}}
{"messageStop": {"stopReason": "end_turn"}}
{"metadata": {"usage": {"inputTokens": 10, "outputTokens": 5}}}
```

## Error Handling

| HTTP Status | Exception | Description |
|-------------|-----------|-------------|
| 429 | `ModelThrottledError` | Rate limited; retry with backoff |
| 400 (overflow) | `ContextWindowOverflowError` | Input too long for model context |
| Other 4xx/5xx | `ModelError` | General model error |

The event loop's `RetryStrategy` handles transient errors (429) automatically with exponential backoff.
