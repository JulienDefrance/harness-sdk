# frozen_string_literal: true

module Strands
  # Typed hook system for extending agent functionality.
  # Provides composable event callbacks for the agent lifecycle.
  module Hooks
    autoload :Registry, "strands/hooks/registry"
    autoload :HookOrder, "strands/hooks/registry"
    autoload :Provider, "strands/hooks/provider"

    # Event classes (defined directly in Strands::Hooks namespace)
    autoload :Event, "strands/hooks/events"
    autoload :AgentEvent, "strands/hooks/events"
    autoload :AgentInitializedEvent, "strands/hooks/events"
    autoload :BeforeInvocationEvent, "strands/hooks/events"
    autoload :AfterInvocationEvent, "strands/hooks/events"
    autoload :MessageAddedEvent, "strands/hooks/events"
    autoload :BeforeToolCallEvent, "strands/hooks/events"
    autoload :AfterToolCallEvent, "strands/hooks/events"
    autoload :BeforeModelCallEvent, "strands/hooks/events"
    autoload :AfterModelCallEvent, "strands/hooks/events"
  end
end
