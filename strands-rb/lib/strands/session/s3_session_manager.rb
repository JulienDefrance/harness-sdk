# frozen_string_literal: true

require "json"
require "securerandom"

module Strands
  module Session
    # S3-backed session manager.
    #
    # Persists conversation state to Amazon S3 via +Storage::S3+. Each session
    # is identified by a unique session ID, and messages are stored as a JSON
    # array under the session key.
    #
    # @example
    #   manager = Strands::Session::S3Manager.new(
    #     bucket: "my-sessions-bucket",
    #     prefix: "agents/"
    #   )
    #   agent = Strands::Agent::Agent.new(session_manager: manager)
    #
    class S3Manager < Manager
      # @return [String] the session identifier
      attr_reader :session_id

      # @return [Strands::Storage::S3] the backing S3 storage
      attr_reader :storage

      # Initialize the S3 session manager.
      #
      # @param bucket [String] the S3 bucket name
      # @param prefix [String] optional key prefix
      # @param session_id [String, nil] session ID (auto-generated if nil)
      # @param region_name [String, nil] AWS region
      def initialize(bucket:, prefix: "", session_id: nil, region_name: nil)
        @session_id = session_id || SecureRandom.uuid
        @storage = Storage::S3.new(bucket: bucket, prefix: prefix, region_name: region_name)
      end

      # Initialize the session for an agent.
      # Restores messages from S3 if the session exists.
      #
      # @param agent [Object] the agent instance
      def initialize_session(agent)
        restore(agent)
      end

      # Append a message to the session.
      # This is a no-op because sync_agent handles full state persistence.
      #
      # @param message [Hash] the message to persist
      # @param agent [Object] the agent instance
      def append_message(message, agent)
        # No-op: handled by sync_agent
      end

      # Sync the full agent conversation state to S3.
      #
      # @param agent [Object] the agent instance
      def sync_agent(agent)
        messages = extract_messages(agent)
        data = JSON.generate({
          session_id: @session_id,
          messages: messages,
          updated_at: Time.now.iso8601
        })
        @storage.write(session_key, data)
      end

      # Restore the agent state from S3.
      #
      # @param agent [Object] the agent instance
      def restore(agent)
        data = @storage.read(session_key)
        return unless data

        parsed = JSON.parse(data)
        restore_messages(agent, parsed["messages"]) if parsed["messages"]
      end

      private

      # The storage key for this session.
      #
      # @return [String]
      def session_key
        "#{@session_id}/state.json"
      end

      # Extract messages from the agent.
      #
      # @param agent [Object]
      # @return [Array<Hash>]
      def extract_messages(agent)
        if agent.respond_to?(:messages)
          agent.messages
        else
          []
        end
      end

      # Restore messages into the agent.
      #
      # @param agent [Object]
      # @param messages [Array<Hash>]
      def restore_messages(agent, messages)
        return unless agent.respond_to?(:messages)

        if agent.messages.respond_to?(:replace)
          agent.messages.replace(messages)
        end
      end
    end
  end
end
