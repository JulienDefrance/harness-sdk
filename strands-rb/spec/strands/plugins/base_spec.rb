# frozen_string_literal: true

require "spec_helper"

RSpec.describe Strands::Plugins::Base do
  let(:agent) { double("agent") }

  describe "plugin_name DSL" do
    it "sets and retrieves the plugin name" do
      plugin_class = Class.new do
        include Strands::Plugins::Base
        plugin_name "test-plugin"
      end

      plugin = plugin_class.new
      expect(plugin.name).to eq("test-plugin")
    end

    it "falls back to class name if plugin_name not set" do
      plugin_class = Class.new do
        include Strands::Plugins::Base
      end

      plugin = plugin_class.new
      expect(plugin.name).to eq(plugin_class.name)
    end
  end

  describe "hook DSL" do
    it "registers hook methods" do
      plugin_class = Class.new do
        include Strands::Plugins::Base
        plugin_name "hook-test"

        hook :on_model_call, event: Strands::Hooks::BeforeModelCallEvent
        def on_model_call(event)
          # handle model call
        end
      end

      plugin = plugin_class.new
      hooks = plugin.hooks

      expect(hooks.length).to eq(1)
      expect(hooks.first[:event]).to eq(Strands::Hooks::BeforeModelCallEvent)
      expect(hooks.first[:order]).to eq(Strands::Hooks::HookOrder::DEFAULT)
    end

    it "supports custom hook ordering" do
      plugin_class = Class.new do
        include Strands::Plugins::Base
        plugin_name "ordered-hooks"

        hook :early_hook, event: Strands::Hooks::BeforeModelCallEvent, order: Strands::Hooks::HookOrder::BEFORE
        def early_hook(event)
        end
      end

      plugin = plugin_class.new
      hooks = plugin.hooks

      expect(hooks.first[:order]).to eq(Strands::Hooks::HookOrder::BEFORE)
    end

    it "discovers multiple hooks" do
      plugin_class = Class.new do
        include Strands::Plugins::Base
        plugin_name "multi-hooks"

        hook :on_model, event: Strands::Hooks::BeforeModelCallEvent
        def on_model(event)
        end

        hook :on_tool, event: Strands::Hooks::BeforeToolCallEvent
        def on_tool(event)
        end
      end

      plugin = plugin_class.new
      hooks = plugin.hooks

      expect(hooks.length).to eq(2)
      events = hooks.map { |h| h[:event] }
      expect(events).to contain_exactly(
        Strands::Hooks::BeforeModelCallEvent,
        Strands::Hooks::BeforeToolCallEvent
      )
    end
  end

  describe "plugin_tool DSL" do
    it "registers tool methods" do
      plugin_class = Class.new do
        include Strands::Plugins::Base
        plugin_name "tool-test"

        plugin_tool :calculator, description: "Performs calculations", schema: { type: "object" }
        def calculator(params)
          params[:a] + params[:b]
        end
      end

      plugin = plugin_class.new
      tools = plugin.tools

      expect(tools.length).to eq(1)
      expect(tools.first[:name]).to eq("calculator")
      expect(tools.first[:description]).to eq("Performs calculations")
      expect(tools.first[:schema]).to eq({ type: "object" })
    end
  end

  describe "#register_hooks" do
    it "registers discovered hooks with a registry" do
      plugin_class = Class.new do
        include Strands::Plugins::Base
        plugin_name "registerable"

        hook :on_model, event: Strands::Hooks::BeforeModelCallEvent
        def on_model(event)
          @called = true
        end
      end

      plugin = plugin_class.new
      registry = Strands::Hooks::Registry.new
      plugin.register_hooks(registry)

      expect(registry.callback_count(Strands::Hooks::BeforeModelCallEvent)).to eq(1)
    end

    it "registered callbacks invoke the plugin method" do
      called_with = nil

      plugin_class = Class.new do
        include Strands::Plugins::Base
        plugin_name "callable-plugin"

        hook :on_model, event: Strands::Hooks::BeforeModelCallEvent
        define_method(:on_model) do |event|
          called_with = event
        end
      end

      plugin = plugin_class.new
      registry = Strands::Hooks::Registry.new
      plugin.register_hooks(registry)

      event = Strands::Hooks::BeforeModelCallEvent.new(agent: agent)
      registry.fire(event)

      expect(called_with).to eq(event)
    end
  end

  describe "inheritance" do
    it "subclasses inherit hook declarations from parent" do
      parent_class = Class.new do
        include Strands::Plugins::Base
        plugin_name "parent-plugin"

        hook :parent_hook, event: Strands::Hooks::BeforeModelCallEvent
        def parent_hook(event)
        end
      end

      child_class = Class.new(parent_class) do
        hook :child_hook, event: Strands::Hooks::BeforeToolCallEvent
        def child_hook(event)
        end
      end

      plugin = child_class.new
      hooks = plugin.hooks

      expect(hooks.length).to eq(2)
    end

    it "subclasses inherit tool declarations from parent" do
      parent_class = Class.new do
        include Strands::Plugins::Base
        plugin_name "parent-tools"

        plugin_tool :parent_tool, description: "parent"
        def parent_tool(params)
        end
      end

      child_class = Class.new(parent_class) do
        plugin_tool :child_tool, description: "child"
        def child_tool(params)
        end
      end

      plugin = child_class.new
      tools = plugin.tools

      expect(tools.length).to eq(2)
    end

    it "child overrides replace parent hook methods" do
      parent_class = Class.new do
        include Strands::Plugins::Base
        plugin_name "override-parent"

        hook :shared_hook, event: Strands::Hooks::BeforeModelCallEvent
        def shared_hook(event)
          "parent"
        end
      end

      child_class = Class.new(parent_class) do
        def shared_hook(event)
          "child"
        end
      end

      plugin = child_class.new
      hooks = plugin.hooks

      # Still one hook, but the callback points to child's method
      expect(hooks.length).to eq(1)
      expect(hooks.first[:callback].call(nil)).to eq("child")
    end
  end

  describe "#init_agent" do
    it "default implementation is a no-op" do
      plugin_class = Class.new do
        include Strands::Plugins::Base
        plugin_name "noop-plugin"
      end

      plugin = plugin_class.new
      expect { plugin.init_agent(agent) }.not_to raise_error
    end

    it "can be overridden for custom initialization" do
      initialized_agent = nil

      plugin_class = Class.new do
        include Strands::Plugins::Base
        plugin_name "init-plugin"

        define_method(:init_agent) do |agent|
          initialized_agent = agent
        end
      end

      plugin = plugin_class.new
      plugin.init_agent(agent)

      expect(initialized_agent).to eq(agent)
    end
  end
end
