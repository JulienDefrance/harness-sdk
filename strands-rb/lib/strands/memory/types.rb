# frozen_string_literal: true

require "securerandom"
require "time"

module Strands
  module Memory
    # A single memory entry retrieved from or stored to a memory store.
    #
    # @attr_accessor id [String] unique identifier
    # @attr_accessor content [String] the memory content
    # @attr_accessor metadata [Hash] additional metadata (scores, tags, etc.)
    # @attr_accessor timestamp [Time] when the memory was created
    # @attr_accessor store_name [String, nil] name of the originating store
    class MemoryEntry
      attr_accessor :id, :content, :metadata, :timestamp, :store_name

      # @param id [String] unique identifier (auto-generated if nil)
      # @param content [String] the memory content
      # @param metadata [Hash] additional metadata
      # @param timestamp [Time] creation timestamp (defaults to now)
      # @param store_name [String, nil] originating store name
      def initialize(content:, id: nil, metadata: nil, timestamp: nil, store_name: nil)
        @id = id || SecureRandom.uuid
        @content = content
        @metadata = metadata || {}
        @timestamp = timestamp || Time.now
        @store_name = store_name
      end

      # Convert the entry to a hash representation.
      #
      # @return [Hash]
      def to_h
        {
          id: @id,
          content: @content,
          metadata: @metadata,
          timestamp: @timestamp.iso8601,
          store_name: @store_name
        }
      end
    end

    # Options for search operations.
    #
    # @attr_accessor max_results [Integer] maximum number of results to return
    class SearchOptions
      attr_accessor :max_results

      # @param max_results [Integer] maximum results (default: 10)
      def initialize(max_results: 10)
        @max_results = max_results
      end
    end
  end
end
