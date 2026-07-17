# frozen_string_literal: true

require "monitor"

module Strands
  module Memory
    # Simple in-memory implementation of the Store interface.
    #
    # Stores entries in a hash keyed by ID. Search is a naive substring
    # match on content, suitable for testing and small workloads.
    #
    # @example
    #   store = Strands::Memory::InMemoryStore.new(name: "facts")
    #   store.add(Strands::Memory::MemoryEntry.new(content: "The sky is blue"))
    #   results = store.search("sky")
    #
    class InMemoryStore
      include Store
      include MonitorMixin

      # @return [String] the name of this store
      attr_reader :name

      # @return [String, nil] description of this store
      attr_reader :description

      # @param name [String] unique store identifier
      # @param description [String, nil] human-readable description
      def initialize(name: "default", description: nil)
        super()
        @name = name
        @description = description
        @entries = {}
      end

      # Add a memory entry to the store.
      #
      # @param entry [Strands::Memory::MemoryEntry] the entry to store
      # @return [void]
      def add(entry)
        synchronize { @entries[entry.id] = entry }
      end

      # Search for entries matching the query (case-insensitive substring match).
      #
      # @param query [String] the search query
      # @param max_results [Integer] maximum results to return (default: 10)
      # @return [Array<Strands::Memory::MemoryEntry>]
      def search(query, max_results: 10, **_opts)
        pattern = query.downcase
        synchronize do
          @entries.values
                  .select { |entry| entry.content.downcase.include?(pattern) }
                  .sort_by { |entry| entry.timestamp }
                  .reverse
                  .first(max_results)
                  .each { |entry| entry.store_name ||= @name }
        end
      end

      # Delete an entry by its ID.
      #
      # @param id [String] the entry identifier
      # @return [Boolean] true if the entry was deleted
      def delete(id)
        synchronize { !@entries.delete(id).nil? }
      end

      # Return the number of entries in the store.
      #
      # @return [Integer]
      def size
        synchronize { @entries.size }
      end

      # Remove all entries.
      #
      # @return [void]
      def clear
        synchronize { @entries.clear }
      end
    end
  end
end
