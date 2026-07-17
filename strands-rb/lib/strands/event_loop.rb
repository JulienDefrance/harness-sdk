# frozen_string_literal: true

module Strands
  # Event loop orchestrating the agent turn cycle:
  # send messages, process model response, handle tool calls, repeat.
  module EventLoop
    autoload :Cycle, "strands/event_loop/cycle"
    autoload :RetryStrategy, "strands/event_loop/retry"
  end
end
