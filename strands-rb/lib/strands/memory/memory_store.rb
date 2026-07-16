# frozen_string_literal: true

module Strands
  module Memory
    # Module defining the interface for memory store backends.
    #
    # Include this module in any class that implements a memory store.
    # Implementations must provide #add, #search, and #delete methods.
    #
    # @example
    #   class MyStore
    #     include Strands::Memory::Store
    #
    #     def add(entry) ... end
    #     def search(query, **opts) ... end
    #     def delete(id) ... end
    #   end
    #
    module Store
      # Add a memory entry to the store.
      #
      # @param entry [Strands::Memory::MemoryEntry] the entry to store
      # @return [void]
      def add(entry)
        raise NotImplementedError, "#{self.class}#add must be implemented"
      end

      # Search the store for entries matching the query.
      #
      # @param query [String] the search query
      # @param opts [Hash] additional search options
      # @option opts [Integer] :max_results maximum results to return
      # @return [Array<Strands::Memory::MemoryEntry>]
      def search(query, **opts)
        raise NotImplementedError, "#{self.class}#search must be implemented"
      end

      # Delete an entry by its ID.
      #
      # @param id [String] the entry identifier
      # @return [Boolean] true if the entry was deleted
      def delete(id)
        raise NotImplementedError, "#{self.class}#delete must be implemented"
      end
    end
  end
end
