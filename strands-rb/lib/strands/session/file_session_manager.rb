# frozen_string_literal: true

require "json"
require "securerandom"

module Strands
  module Session
    # File-based session manager using LocalFile storage.
    #
    # Persists conversation state to the filesystem. Each session is identified
    # by a unique session ID, and messages are stored as a JSON array.
    #
    # @example
    #   manager = Strands::Session::FileManager.new(
    #     base_dir: "./.strands/sessions"
    #   )
    #   agent = Strands::Agent::Agent.new(session_manager: manager)
    #
    class FileManager < Manager
      # @return [String] the session identifier
      attr_reader :session_id

      # @return [Strands::Storage::LocalFile] the backing storage
      attr_reader :storage

      # @param base_dir [String] base directory for session files
      # @param session_id [String, nil] session ID (auto-generated if nil)
      def initialize(base_dir: "./.strands/sessions", session_id: nil)
        @session_id = session_id || SecureRandom.uuid
        @storage = Storage::LocalFile.new(base_dir: base_dir)
      end

      # Initialize the session for an agent.
      # Restores messages from the session file if it exists.
      #
      # @param agent [Object] the agent instance
      def initialize_session(agent)
        restore(agent)
      end

      # Append a message to the session storage.
      #
      # @param message [Hash] the message to persist
      # @param agent [Object] the agent instance
      def append_message(message, agent)
        # We sync the full state on each message addition,
        # so this is effectively handled by sync_agent
      end

      # Sync the full agent conversation state to storage.
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

      # Restore the agent state from the session file.
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
