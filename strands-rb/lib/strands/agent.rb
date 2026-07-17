# frozen_string_literal: true

module Strands
  # Core agent module providing the primary interface for interacting with
  # foundation models and tools.
  module Agent
    autoload :Agent, "strands/agent/agent"
    autoload :Result, "strands/agent/agent_result"
    autoload :ToolCaller, "strands/agent/agent"
    autoload :ConversationManager, "strands/agent/conversation_manager"
    autoload :NullConversationManager, "strands/agent/conversation_manager"
    autoload :SlidingWindowConversationManager, "strands/agent/conversation_manager"
  end
end
