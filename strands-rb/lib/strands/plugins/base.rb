# frozen_string_literal: true

module Strands
  module Plugins
    # Base module for plugins that extend agent functionality.
    #
    # Include this module in any class that acts as a plugin. It provides
    # auto-discovery of hook and tool methods, and integrates with the
    # hook registry for automatic registration.
    #
    # Hooks are declared using the class-level `hook` method, which annotates
    # instance methods as hook callbacks. Tools are declared using the `plugin_tool`
    # class method.
    #
    # @example
    #   class MyPlugin
    #     include Strands::Plugins::Base
    #
    #     plugin_name "my-plugin"
    #
    #     hook :on_model_call, event: Strands::Hooks::BeforeModelCallEvent
    #     def on_model_call(event)
    #       puts "Model called!"
    #     end
    #
    #     plugin_tool :my_tool, description: "Does something"
    #     def my_tool(params)
    #       "Result: #{params}"
    #     end
    #   end
    #
    module Base
      def self.included(base)
        base.extend(ClassMethods)
        base.instance_variable_set(:@_hook_methods, [])
        base.instance_variable_set(:@_tool_methods, [])
        base.instance_variable_set(:@_plugin_name, nil)
      end

      # Class-level DSL methods for declaring hooks and tools.
      module ClassMethods
        # Set the plugin name.
        #
        # @param name [String] a stable string identifier for the plugin
        def plugin_name(name)
          @_plugin_name = name
        end

        # Retrieve the configured plugin name.
        #
        # @return [String, nil]
        def registered_plugin_name
          @_plugin_name
        end

        # Declare a method as a hook callback.
        #
        # @param method_name [Symbol] the method name to register as a hook
        # @param event [Class] the event class this hook handles
        # @param order [Integer] execution priority
        def hook(method_name, event:, order: Hooks::HookOrder::DEFAULT)
          @_hook_methods << { method_name: method_name, event: event, order: order }
        end

        # Declare a method as a plugin tool.
        #
        # @param method_name [Symbol] the method name to register as a tool
        # @param description [String] human-readable description
        # @param schema [Hash] JSON Schema for input parameters
        def plugin_tool(method_name, description: "", schema: {})
          @_tool_methods << { method_name: method_name, description: description, schema: schema }
        end

        # Get the declared hook methods.
        #
        # @return [Array<Hash>]
        def hook_methods
          @_hook_methods
        end

        # Get the declared tool methods.
        #
        # @return [Array<Hash>]
        def tool_methods
          @_tool_methods
        end

        # Inherited hook to ensure subclasses inherit parent declarations.
        def inherited(subclass)
          super
          subclass.instance_variable_set(:@_hook_methods, @_hook_methods.dup)
          subclass.instance_variable_set(:@_tool_methods, @_tool_methods.dup)
          subclass.instance_variable_set(:@_plugin_name, @_plugin_name)
        end
      end

      # The plugin name.
      #
      # @return [String]
      def name
        self.class.registered_plugin_name || self.class.name
      end

      # Discover and return hook callbacks for this plugin instance.
      #
      # @return [Array<Hash{event:, callback:, order:}>]
      def hooks
        Discovery.discover_hooks(self)
      end

      # Discover and return tool definitions for this plugin instance.
      #
      # @return [Array<Hash{name:, description:, schema:, callable:}>]
      def tools
        Discovery.discover_tools(self)
      end

      # Register all discovered hooks with a hook registry.
      #
      # @param registry [Strands::Hooks::Registry] the hook registry
      def register_hooks(registry)
        hooks.each do |hook_info|
          registry.add_callback(hook_info[:event], order: hook_info[:order], &hook_info[:callback])
        end
      end

      # Initialize the plugin with an agent.
      # Override this method for custom initialization logic.
      #
      # @param agent [Object] the agent instance
      def init_agent(agent)
        # Default no-op; subclasses can override
      end
    end
  end
end
