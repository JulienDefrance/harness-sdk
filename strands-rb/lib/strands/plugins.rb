# frozen_string_literal: true

module Strands
  # Plugin system for composing hooks, tools, and interventions.
  module Plugins
    autoload :Base, "strands/plugins/base"
    autoload :Discovery, "strands/plugins/discovery"
    autoload :Registry, "strands/plugins/registry"
  end
end
