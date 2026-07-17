# frozen_string_literal: true

require "fileutils"
require "json"
require "securerandom"
require "tmpdir"

module Strands
  module Storage
    # Filesystem-backed storage that persists each key as a file.
    #
    # Key segments separated by '/' map to directory segments under the base
    # directory. Writes are atomic (write to temp file, then rename).
    #
    # @example
    #   storage = Strands::Storage::LocalFile.new(base_dir: "./.strands/")
    #   storage.write("sessions/abc/state.json", '{"messages": []}')
    #   data = storage.read("sessions/abc/state.json")
    #
    class LocalFile
      include Base

      TMP_MARKER = ".__strands_tmp"

      # @return [String] the base directory for storage
      attr_reader :base_dir

      # @param base_dir [String] root directory for file storage
      def initialize(base_dir: File.join(Dir.tmpdir, ".strands"))
        @base_dir = File.expand_path(base_dir)
      end

      # Read the file corresponding to the given key.
      #
      # @param key [String] the storage key
      # @return [String, nil] the file contents, or nil if not found
      def read(key)
        normalized = normalize_key(key)
        path = path_for(normalized)
        return nil unless File.exist?(path)

        File.read(path)
      rescue Errno::ENOENT, Errno::ENOTDIR
        nil
      end

      # Store data as a file, creating parent directories as needed.
      # Writes are atomic via write-to-temp-then-rename.
      #
      # @param key [String] the storage key
      # @param data [String] the data to store
      # @return [void]
      def write(key, data)
        normalized = normalize_key(key)
        path = path_for(normalized)
        parent = File.dirname(path)

        FileUtils.mkdir_p(parent)

        tmp_path = File.join(parent, "#{TMP_MARKER}_#{SecureRandom.hex(8)}")
        begin
          File.write(tmp_path, data)
          File.rename(tmp_path, path)
        rescue StandardError
          FileUtils.rm_f(tmp_path)
          raise
        end
      end

      # Delete the file corresponding to key. No-op if it does not exist.
      #
      # @param key [String] the storage key
      # @return [void]
      def delete(key)
        normalized = normalize_key(key)
        path = path_for(normalized)
        FileUtils.rm_f(path)
      end

      # Check whether a file exists for the given key.
      #
      # @param key [String] the storage key
      # @return [Boolean]
      def exists?(key)
        normalized = normalize_key(key)
        File.exist?(path_for(normalized))
      end

      # List keys matching the given prefix by walking the directory tree.
      #
      # @param prefix [String] a prefix to filter keys (empty string matches all)
      # @return [Array<String>] matching keys sorted ascending
      def list(prefix = "")
        normalized_prefix = normalize_prefix(prefix)

        return [] unless Dir.exist?(@base_dir)

        keys = []
        Dir.glob(File.join(@base_dir, "**", "*")).each do |full_path|
          next unless File.file?(full_path)
          next if full_path.include?(TMP_MARKER)

          rel = full_path.sub("#{@base_dir}/", "")
          keys << rel if rel.start_with?(normalized_prefix)
        end

        keys.sort
      end

      private

      # Map a normalized key to a filesystem path.
      #
      # @param key [String] the normalized key
      # @return [String] the full filesystem path
      def path_for(key)
        File.join(@base_dir, key)
      end
    end
  end
end
