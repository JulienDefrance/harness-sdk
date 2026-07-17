# frozen_string_literal: true

module Strands
  module Plugins
    # Helper methods for discovering hook and tool methods on plugin instances.
    #
    # Scans the plugin class hierarchy for methods annotated via the
    # `hook` and `plugin_tool` class-level DSL methods.
    module Discovery
      class << self
        # Discover hook methods on a plugin instance.
        #
        # @param instance [Object] the plugin instance (must include Strands::Plugins::Base)
        # @return [Array<Hash{event:, callback:, order:}>]
        def discover_hooks(instance)
          klass = instance.class
          hook_methods = collect_hook_methods(klass)

          hook_methods.map do |hook_info|
            {
              event: hook_info[:event],
              order: hook_info[:order],
              callback: instance.method(hook_info[:method_name])
            }
          end
        end

        # Discover tool methods on a plugin instance.
        #
        # @param instance [Object] the plugin instance (must include Strands::Plugins::Base)
        # @return [Array<Hash{name:, description:, schema:, callable:}>]
        def discover_tools(instance)
          klass = instance.class
          tool_methods = collect_tool_methods(klass)

          tool_methods.map do |tool_info|
            {
              name: tool_info[:method_name].to_s,
              description: tool_info[:description],
              schema: tool_info[:schema],
              callable: instance.method(tool_info[:method_name])
            }
          end
        end

        private

        # Walk the class hierarchy (MRO) collecting hook declarations.
        # Parent class methods come first, child overrides win.
        #
        # @param klass [Class] the plugin class
        # @return [Array<Hash>]
        def collect_hook_methods(klass)
          all_hooks = []
          seen = {}

          # Walk ancestors in reverse so parent hooks come first,
          # but child overrides replace them
          ancestors_with_hooks(klass).reverse_each do |ancestor|
            next unless ancestor.respond_to?(:hook_methods)

            ancestor.hook_methods.each do |hook_info|
              method_name = hook_info[:method_name]
              seen[method_name] = hook_info
            end
          end

          seen.values
        end

        # Walk the class hierarchy (MRO) collecting tool declarations.
        #
        # @param klass [Class] the plugin class
        # @return [Array<Hash>]
        def collect_tool_methods(klass)
          all_tools = []
          seen = {}

          ancestors_with_hooks(klass).reverse_each do |ancestor|
            next unless ancestor.respond_to?(:tool_methods)

            ancestor.tool_methods.each do |tool_info|
              method_name = tool_info[:method_name]
              seen[method_name] = tool_info
            end
          end

          seen.values
        end

        # Get ancestors that have hook/tool method declarations.
        #
        # @param klass [Class] the plugin class
        # @return [Array<Class>]
        def ancestors_with_hooks(klass)
          klass.ancestors.select do |ancestor|
            ancestor.is_a?(Class) && ancestor.respond_to?(:hook_methods)
          end
        end
      end
    end
  end
end
