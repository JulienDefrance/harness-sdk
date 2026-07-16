# frozen_string_literal: true

module Strands
  module Storage
    # Base module defining the storage interface.
    #
    # Include this module in any class that implements a persistence backend.
    # Implementations must provide #read, #write, #delete, and #exists? methods.
    #
    # Keys are opaque, '/'-separated strings. Implementations should treat them
    # as path-like identifiers.
    #
    # @example
    #   class MyStorage
    #     include Strands::Storage::Base
    #
    #     def read(key) ... end
    #     def write(key, data) ... end
    #     def delete(key) ... end
    #     def exists?(key) ... end
    #     def list(prefix = "") ... end
    #   end
    #
    module Base
      # Read data stored under the given key.
      #
      # @param key [String] the storage key
      # @return [String, nil] the stored data, or nil if not found
      def read(key)
        raise NotImplementedError, "#{self.class}#read must be implemented"
      end

      # Write data under the given key, overwriting any existing value.
      #
      # @param key [String] the storage key
      # @param data [String] the data to store
      # @return [void]
      def write(key, data)
        raise NotImplementedError, "#{self.class}#write must be implemented"
      end

      # Delete the value stored under key. No-op if key does not exist.
      #
      # @param key [String] the storage key
      # @return [void]
      def delete(key)
        raise NotImplementedError, "#{self.class}#delete must be implemented"
      end

      # Check whether a value exists for the given key.
      #
      # @param key [String] the storage key
      # @return [Boolean]
      def exists?(key)
        raise NotImplementedError, "#{self.class}#exists? must be implemented"
      end

      # List keys matching the given prefix.
      #
      # @param prefix [String] a prefix to filter keys (empty string matches all)
      # @return [Array<String>] matching keys sorted ascending
      def list(prefix = "")
        raise NotImplementedError, "#{self.class}#list must be implemented"
      end

      private

      # Normalize a storage key by collapsing slashes, stripping leading/trailing slashes,
      # and rejecting empty keys or '..' segments.
      #
      # @param key [String] the raw key
      # @return [String] the normalized key
      # @raise [ArgumentError] if the key is empty or contains '..'
      def normalize_key(key)
        normalized = key.gsub(%r{/+}, "/").gsub(%r{^/|/$}, "")
        raise ArgumentError, "Storage key must not be empty" if normalized.empty?
        raise ArgumentError, "Invalid storage key '#{key}': '..' segments are not allowed" if normalized.split("/").include?("..")

        normalized
      end

      # Normalize a list prefix.
      #
      # @param prefix [String] the raw prefix
      # @return [String] the normalized prefix
      # @raise [ArgumentError] if the prefix contains '..'
      def normalize_prefix(prefix)
        normalized = prefix.gsub(%r{/+}, "/").gsub(%r{^/}, "")
        if normalized.split("/").include?("..")
          raise ArgumentError, "Invalid storage prefix '#{prefix}': '..' segments are not allowed"
        end

        normalized
      end
    end
  end
end
