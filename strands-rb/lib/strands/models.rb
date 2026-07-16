# frozen_string_literal: true

module Strands
  # Model providers for AI foundation models.
  # Each provider implements the streaming interface defined by Models::Base.
  module Models
    autoload :Base, "strands/models/base"
    autoload :StreamEventBuilder, "strands/models/stream_event_builder"
    autoload :OpenAI, "strands/models/openai"
    autoload :Bedrock, "strands/models/bedrock"
    autoload :Anthropic, "strands/models/anthropic"
    autoload :Ollama, "strands/models/ollama"
  end
end
