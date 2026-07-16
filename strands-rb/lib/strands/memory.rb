# frozen_string_literal: true

module Strands
  # Cross-session memory system for recalling facts and decisions.
  module Memory
    autoload :Store, "strands/memory/memory_store"
    autoload :MemoryEntry, "strands/memory/types"
    autoload :SearchOptions, "strands/memory/types"
    autoload :InMemoryStore, "strands/memory/in_memory_store"
    autoload :Manager, "strands/memory/memory_manager"
  end
end
