# frozen_string_literal: true

module Strands
  # Shared type definitions for content blocks, streaming events,
  # tool specifications, media types, and custom exceptions.
  module Types
    autoload :Content, "strands/types/content"
    autoload :EventLoop, "strands/types/event_loop"
    autoload :Exceptions, "strands/types/exceptions"
    autoload :Media, "strands/types/media"
    autoload :Streaming, "strands/types/streaming"
    autoload :Tools, "strands/types/tools"
  end
end
