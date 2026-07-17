# frozen_string_literal: true

module Strands
  module Memory
    # Manager that coordinates multiple memory stores, providing search
    # and add capabilities as a plugin.
    #
    # The Manager acts as a Plugins::Base and exposes search/add as tools
    # that the agent can invoke. It also supports programmatic search and add.
    #
    # @example
    #   store = Strands::Memory::InMemoryStore.new(name: "facts")
    #   manager = Strands::Memory::Manager.new(stores: [store])
    #   manager.add("The sky is blue", stores: ["facts"])
    #   results = manager.search("sky")
    #
    class Manager
      include Plugins::Base

      plugin_name "memory-manager"

      plugin_tool :search_memory, description: "Search memory stores for relevant entries",
                                  schema: {
                                    type: "object",
                                    properties: {
                                      query: { type: "string", description: "Search query" },
                                      max_results: { type: "integer", description: "Maximum results per store" }
                                    },
                                    required: ["query"]
                                  }

      plugin_tool :add_memory, description: "Add a new memory entry to stores",
                               schema: {
                                 type: "object",
                                 properties: {
                                   content: { type: "string", description: "Content to remember" },
                                   metadata: { type: "object", description: "Optional metadata" }
                                 },
                                 required: ["content"]
                               }

      # @return [Array<Strands::Memory::Store>] managed stores
      attr_reader :stores

      # @param stores [Array<Object>] store instances implementing the Store interface
      # @param default_max_results [Integer] default max results per search
      def initialize(stores: [], default_max_results: 10)
        @stores = stores
        @default_max_results = default_max_results
      end

      # Search across all (or filtered) stores for entries matching the query.
      #
      # @param query [String] the search query
      # @param max_results [Integer] maximum results per store
      # @param stores [Array<String>, nil] filter to specific store names
      # @return [Array<Strands::Memory::MemoryEntry>]
      def search(query, max_results: @default_max_results, stores: nil)
        target_stores = resolve_stores(stores)
        results = []

        target_stores.each do |store|
          entries = store.search(query, max_results: max_results)
          entries.each { |entry| entry.store_name ||= store.name }
          results.concat(entries)
        end

        results
      end

      # Add content as a memory entry to all (or filtered) writable stores.
      #
      # @param content [String] the content to remember
      # @param metadata [Hash] optional metadata
      # @param stores [Array<String>, nil] filter to specific store names
      # @return [Strands::Memory::MemoryEntry] the created entry
      def add(content, metadata: {}, stores: nil)
        target_stores = resolve_stores(stores)
        entry = MemoryEntry.new(content: content, metadata: metadata)

        target_stores.each { |store| store.add(entry) }

        entry
      end

      # Tool handler for search_memory.
      #
      # @param params [Hash] tool parameters
      # @return [Hash] search results
      def search_memory(params)
        query = params[:query] || params["query"]
        max_results = params[:max_results] || params["max_results"] || @default_max_results

        entries = search(query, max_results: max_results)
        {
          results: entries.map(&:to_h),
          count: entries.size
        }
      end

      # Tool handler for add_memory.
      #
      # @param params [Hash] tool parameters
      # @return [Hash] confirmation
      def add_memory(params)
        content = params[:content] || params["content"]
        metadata = params[:metadata] || params["metadata"] || {}

        entry = add(content, metadata: metadata)
        {
          stored: true,
          id: entry.id,
          content: entry.content
        }
      end

      private

      # Resolve store names to store instances.
      #
      # @param store_names [Array<String>, nil] store names to filter by
      # @return [Array<Object>] resolved stores
      def resolve_stores(store_names)
        return @stores if store_names.nil? || store_names.empty?

        @stores.select { |store| store_names.include?(store.name) }
      end
    end
  end
end
