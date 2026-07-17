# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("lib", __dir__)
require "strands/version"

Gem::Specification.new do |spec|
  spec.name = "strands"
  spec.version = Strands::VERSION
  spec.authors = ["Strands Contributors"]
  spec.email = ["strands@example.com"]

  spec.summary = "A framework for building, deploying, and managing AI agents"
  spec.description = "Strands Ruby SDK provides a composable framework for building AI agents " \
                     "with support for multiple model providers, tool execution, hooks, " \
                     "interventions, and session management."
  spec.homepage = "https://github.com/strands-agents/strands-rb"
  spec.license = "Apache-2.0"
  spec.required_ruby_version = ">= 4.0.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/strands-agents/strands-rb"
  spec.metadata["changelog_uri"] = "https://github.com/strands-agents/strands-rb/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir.glob("lib/**/*") + %w[LICENSE README.md]
  spec.require_paths = ["lib"]

  # No runtime dependencies - uses only Ruby stdlib
  # (json, net/http, logger, securerandom, fileutils, uri, monitor, openssl)
end
