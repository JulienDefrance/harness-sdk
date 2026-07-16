# frozen_string_literal: true

module Strands
  module Storage
    # Amazon S3 storage backend.
    #
    # Persists data to an S3 bucket. The aws-sdk-s3 gem is lazily loaded
    # on first use so that applications not using S3 storage do not need
    # the dependency installed.
    #
    # @example
    #   storage = Strands::Storage::S3.new(bucket: "my-bucket", prefix: "strands/")
    #   storage.write("sessions/abc/state.json", '{"messages": []}')
    #   data = storage.read("sessions/abc/state.json")
    #
    class S3
      include Base

      # @return [String] the S3 bucket name
      attr_reader :bucket

      # @return [String] the key prefix applied to all operations
      attr_reader :prefix

      # Initialize the S3 storage backend.
      #
      # @param bucket [String] the S3 bucket name
      # @param prefix [String] optional key prefix for all operations
      # @param region_name [String, nil] AWS region (uses SDK default if nil)
      def initialize(bucket:, prefix: "", region_name: nil)
        @bucket = bucket
        @prefix = prefix.gsub(%r{/+$}, "")
        @prefix = "#{@prefix}/" unless @prefix.empty?
        @region_name = region_name
        @client = nil
      end

      # Read the object stored under the given key.
      #
      # @param key [String] the storage key
      # @return [String, nil] the object body, or nil if not found
      def read(key)
        normalized = normalize_key(key)
        full_key = "#{@prefix}#{normalized}"
        response = client.get_object(bucket: @bucket, key: full_key)
        response.body.read
      rescue StandardError => e
        return nil if no_such_key_error?(e)

        raise
      end

      # Write data to S3 under the given key.
      #
      # @param key [String] the storage key
      # @param data [String] the data to store
      # @return [void]
      def write(key, data)
        normalized = normalize_key(key)
        full_key = "#{@prefix}#{normalized}"
        client.put_object(bucket: @bucket, key: full_key, body: data)
      end

      # Delete the object under key. No-op if it does not exist.
      #
      # @param key [String] the storage key
      # @return [void]
      def delete(key)
        normalized = normalize_key(key)
        full_key = "#{@prefix}#{normalized}"
        client.delete_object(bucket: @bucket, key: full_key)
      end

      # Check whether an object exists for the given key.
      #
      # @param key [String] the storage key
      # @return [Boolean]
      def exists?(key)
        normalized = normalize_key(key)
        full_key = "#{@prefix}#{normalized}"
        client.head_object(bucket: @bucket, key: full_key)
        true
      rescue StandardError => e
        return false if not_found_error?(e)

        raise
      end

      # List keys matching the given prefix.
      #
      # Handles pagination via continuation tokens. Returns keys with the
      # storage-level prefix stripped.
      #
      # @param prefix [String] a prefix to filter keys (empty string matches all)
      # @return [Array<String>] matching keys sorted ascending
      def list(prefix = "")
        normalized_prefix = normalize_prefix(prefix)
        full_prefix = "#{@prefix}#{normalized_prefix}"

        keys = []
        continuation_token = nil

        loop do
          params = { bucket: @bucket, prefix: full_prefix }
          params[:continuation_token] = continuation_token if continuation_token

          response = client.list_objects_v2(**params)

          (response.contents || []).each do |obj|
            # Strip the storage-level prefix from the key
            relative_key = obj.key.sub(/\A#{Regexp.escape(@prefix)}/, "")
            keys << relative_key
          end

          break unless response.is_truncated

          continuation_token = response.next_continuation_token
          break unless continuation_token
        end

        keys.sort
      end

      private

      # Lazily creates the S3 client, loading the gem on first access.
      #
      # @return [Aws::S3::Client] the S3 client
      # @raise [Strands::Error] if the aws-sdk-s3 gem is not available
      def client
        @client ||= begin
          require "aws-sdk-s3"
          options = {}
          options[:region] = @region_name if @region_name
          Aws::S3::Client.new(**options)
        rescue LoadError
          raise Strands::Error, "aws-sdk-s3 gem is required for S3 storage. Add gem 'aws-sdk-s3' to your Gemfile."
        end
      end

      # Check if an error indicates a missing key.
      #
      # @param error [StandardError] the error to check
      # @return [Boolean]
      def no_such_key_error?(error)
        error.class.name == "Aws::S3::Errors::NoSuchKey" ||
          (error.respond_to?(:code) && error.code == "NoSuchKey")
      end

      # Check if an error indicates a not-found response.
      #
      # @param error [StandardError] the error to check
      # @return [Boolean]
      def not_found_error?(error)
        error.class.name == "Aws::S3::Errors::NotFound" ||
          error.class.name == "Aws::S3::Errors::NoSuchKey" ||
          (error.respond_to?(:code) && %w[NotFound NoSuchKey].include?(error.code))
      end
    end
  end
end
