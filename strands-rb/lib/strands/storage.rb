# frozen_string_literal: true

module Strands
  # Persistence backends for agent state.
  module Storage
    autoload :Base, "strands/storage/base"
    autoload :InMemory, "strands/storage/in_memory"
    autoload :LocalFile, "strands/storage/local_file"
    autoload :S3, "strands/storage/s3"
  end
end
