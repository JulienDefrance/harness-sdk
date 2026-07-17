# frozen_string_literal: true

require "monitor"

module Strands
  module Storage
    # Hash-backed in-memory storage for testing and short-lived processes.
    #
    # Data does not survive process restarts. The store is unbounded;
    # consumers manage eviction themselves.
    #
    # @example
    #   storage = Strands::Storage::InMemory.new
    #   storage.write("sessions/abc/state.json", '{"messages": []}')
    #   data = storage.read("sessions/abc/state.json")
    #
    class InMemory
      include Base
      include MonitorMixin

      def initialize
        super
        @store = {}
      end

      # Read data stored under the given key.
      #
      # @param key [String] the storage key
      # @return [String, nil] the stored data, or nil if not found
      def read(key)
        normalized = normalize_key(key)
        synchronize { @store[normalized] }
      end

      # Write data under the given key, overwriting any existing value.
      #
      # @param key [String] the storage key
      # @param data [String] the data to store
      # @return [void]
      def write(key, data)
        normalized = normalize_key(key)
        synchronize { @store[normalized] = data.dup.freeze }
      end

      # Delete the value stored under key. No-op if key does not exist.
      #
      # @param key [String] the storage key
      # @return [void]
      def delete(key)
        normalized = normalize_key(key)
        synchronize { @store.delete(normalized) }
      end

      # Check whether a value exists for the given key.
      #
      # @param key [String] the storage key
      # @return [Boolean]
      def exists?(key)
        normalized = normalize_key(key)
        synchronize { @store.key?(normalized) }
      end

      # List keys matching the given prefix.
      #
      # @param prefix [String] a prefix to filter keys (empty string matches all)
      # @return [Array<String>] matching keys sorted ascending
      def list(prefix = "")
        normalized_prefix = normalize_prefix(prefix)
        synchronize do
          @store.keys.select { |k| k.start_with?(normalized_prefix) }.sort
        end
      end

      # Remove all stored entries.
      #
      # @return [void]
      def clear
        synchronize { @store.clear }
      end

      # Return the number of stored entries.
      #
      # @return [Integer]
      def size
        synchronize { @store.size }
      end
    end
  end
end
