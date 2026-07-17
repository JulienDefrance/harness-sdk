# frozen_string_literal: true

module Strands
  # Session management for persisting agent conversations across interactions.
  module Session
    autoload :Manager, "strands/session/session_manager"
    autoload :FileManager, "strands/session/file_session_manager"
    autoload :S3Manager, "strands/session/s3_session_manager"
  end
end
