# frozen_string_literal: true

module Strands
  module Agent
    # Core Agent class that orchestrates model calls, tool execution, and hooks.
    #
    # The Agent is the primary entry point for interacting with foundation models.
    # It manages the conversation history, tool registry, hook system, interventions,
    # and delegates to the EventLoop::Cycle for turn processing.
    #
    # == Thread Safety
    #
    # This class is NOT thread-safe. Concurrent calls to {#call} or {#invoke} on the
    # same Agent instance will corrupt conversation state (+@messages+). Each thread
    # should use its own Agent instance, or external synchronization must be applied.
    # The +@messages+ array and the conversation manager's +apply+ method both perform
    # non-atomic read-modify-write sequences that are unsafe under concurrent access.
    #
    # @example Basic usage
    #   agent = Strands::Agent::Agent.new(
    #     model: Strands::Models::OpenAI.new(model_id: "gpt-4"),
    #     system_prompt: "You are a helpful assistant."
    #   )
    #   result = agent.call("What is 2 + 2?")
    #   puts result.text
    #
    # @example Using the default model (Bedrock)
    #   # When no model is given, the Agent defaults to Strands::Models::Bedrock,
    #   # which requires AWS credentials to be configured (see Bedrock docs).
    #   agent = Strands::Agent::Agent.new(system_prompt: "You are a helpful assistant.")
    #   result = agent.call("What is 2 + 2?")
    #
    # @example With tools
    #   calculator = Strands.tool("calculator",
    #     description: "Evaluates math expressions",
    #     schema: { properties: { expr: { type: "string" } }, required: ["expr"] }
    #   ) { |expr:| eval(expr).to_s }
    #
    #   agent = Strands::Agent::Agent.new(tools: [calculator])
    #   result = agent.call("What is 123 * 456?")
    #
    # @example Direct tool invocation
    #   agent.tool.calculator(expr: "2 + 2")
    #
    class Agent
      # @return [Object] the model provider instance
      attr_reader :model

      # @return [String, nil] the system prompt
      attr_reader :system_prompt

      # @return [Array<Hash>] the conversation message history
      attr_accessor :messages

      # @return [Strands::Tools::Registry] the tool registry
      attr_reader :tool_registry

      # @return [Strands::Hooks::Registry] the hook registry
      attr_reader :hook_registry

      # @return [Object, nil] the callback handler for streaming output
      attr_reader :callback_handler

      # @return [ConversationManager] the conversation manager
      attr_reader :conversation_manager

      # @return [String] the agent name
      attr_reader :name

      # @return [EventLoop::RetryStrategy] the retry strategy
      attr_reader :retry_strategy

      # @return [Integer] maximum turns in the event loop
      attr_reader :max_turns

      # Creates a new Agent.
      #
      # @param model [Object, nil] model provider (must implement Models::Base). Defaults to
      #   {Strands::Models::Bedrock} (using its own default model_id) when not specified,
      #   matching the Python and TypeScript SDKs. Pass a model explicitly to pin behavior
      #   or to use a different provider.
      # @param tools [Array] tools to register (Definition, Hash, or callable objects)
      # @param system_prompt [String, nil] system prompt for model context
      # @param hooks [Array<Object>] hook providers implementing #register_hooks
      # @param interventions [Array<Interventions::Handler>] intervention handlers
      # @param plugins [Array<Object>] plugins implementing Plugins::Base
      # @param callback_handler [Object, nil] handler for streaming events (responds to #call)
      # @param conversation_manager [ConversationManager, nil] manages message history trimming
      # @param retry_strategy [EventLoop::RetryStrategy, nil] retry configuration
      # @param max_turns [Integer] maximum event loop turns (default: 50)
      # @param name [String] agent name (default: "Strands Agent")
      def initialize(
        model: nil,
        tools: [],
        system_prompt: nil,
        hooks: [],
        interventions: [],
        plugins: [],
        callback_handler: nil,
        conversation_manager: nil,
        retry_strategy: nil,
        max_turns: EventLoop::Cycle::DEFAULT_MAX_TURNS,
        name: "Strands Agent"
      )
        @model = model || Models::Bedrock.new
        @system_prompt = system_prompt
        @messages = []
        @name = name
        @max_turns = max_turns
        @retry_strategy = retry_strategy || EventLoop::RetryStrategy.new

        # Set up callback handler
        @callback_handler = callback_handler

        # Set up conversation manager
        @conversation_manager = conversation_manager || NullConversationManager.new

        # Set up tool registry
        @tool_registry = Tools::Registry.new
        register_tools(tools)

        # Set up hook registry
        @hook_registry = Hooks::Registry.new
        register_hooks(hooks)

        # Set up interventions
        register_interventions(interventions)

        # Set up plugins
        register_plugins(plugins)

        # Fire AgentInitializedEvent
        fire_initialized_event
      end

      # Invoke the agent with a user prompt.
      #
      # This is the primary interface for interacting with the agent.
      # It adds the user message to the conversation, runs the event loop,
      # and returns the result.
      #
      # @param prompt [String] the user's message
      # @param invocation_state [Hash] additional state for this invocation
      # @return [Result] the agent's response
      def call(prompt, invocation_state: {})
        # Fire BeforeInvocationEvent
        before_event = Hooks::BeforeInvocationEvent.new(
          agent: self,
          invocation_state: invocation_state,
          messages: @messages
        )
        @hook_registry.fire(before_event)

        # Check if invocation was cancelled
        if before_event.cancel
          cancel_text = before_event.cancel.is_a?(String) ? before_event.cancel : "Invocation denied"
          message = { role: :assistant, content: [{ text: cancel_text }] }
          result = Result.new(stop_reason: :end_turn, message: message, state: invocation_state)
          fire_after_invocation(invocation_state, result)
          return result
        end

        # Add user message
        user_message = { role: :user, content: [{ text: prompt }] }
        @messages << user_message

        # Apply conversation manager
        @messages = @conversation_manager.apply(@messages, model: @model)

        # Run the event loop cycle
        cycle = EventLoop::Cycle.new(
          agent: self,
          retry_strategy: @retry_strategy,
          max_turns: @max_turns
        )
        cycle_result = cycle.run(invocation_state: invocation_state)

        result = Result.new(
          stop_reason: cycle_result[:stop_reason],
          message: cycle_result[:message],
          metrics: cycle_result[:metrics] || {},
          state: invocation_state
        )

        # Fire AfterInvocationEvent
        fire_after_invocation(invocation_state, result)

        result
      end

      # Alias for #call.
      #
      # @param prompt [String] the user's message
      # @param kwargs [Hash] additional keyword arguments
      # @return [Result]
      def invoke(prompt, **kwargs)
        call(prompt, **kwargs)
      end

      # Returns a ToolCaller proxy for direct tool invocation.
      #
      # @return [ToolCaller]
      #
      # @example
      #   agent.tool.calculator(expr: "2 + 2")
      #
      def tool
        @tool_caller ||= ToolCaller.new(self)
      end

      private

      # Register tools from constructor arguments.
      #
      # @param tools [Array] tools to register
      def register_tools(tools)
        @tool_registry.process_tools(tools) if tools && !tools.empty?
      end

      # Register hook providers.
      #
      # @param hooks [Array] hook providers
      def register_hooks(hooks)
        hooks.each do |hook_provider|
          @hook_registry.add_hook(hook_provider)
        end
      end

      # Register intervention handlers into the hook system.
      #
      # @param interventions [Array<Interventions::Handler>] handlers
      def register_interventions(interventions)
        return if interventions.empty?

        Interventions::Registry.new(
          handlers: interventions,
          hook_registry: @hook_registry
        )
      end

      # Register plugins (each may provide hooks and tools).
      #
      # @param plugins [Array] plugin instances
      def register_plugins(plugins)
        plugins.each do |plugin|
          # Register plugin hooks
          plugin.register_hooks(@hook_registry) if plugin.respond_to?(:register_hooks)

          # Register plugin tools
          if plugin.respond_to?(:tools)
            plugin.tools.each do |tool_info|
              definition = Tools::Definition.new(
                name: tool_info[:name],
                description: tool_info[:description] || "",
                input_schema: tool_info[:schema] || {},
                callable: tool_info[:callable]
              )
              @tool_registry.register(definition)
            end
          end

          # Initialize plugin with agent reference
          plugin.init_agent(self) if plugin.respond_to?(:init_agent)
        end
      end

      # Fire the AgentInitializedEvent.
      def fire_initialized_event
        event = Hooks::AgentInitializedEvent.new(agent: self)
        @hook_registry.fire(event)
      end

      # Fire the AfterInvocationEvent.
      #
      # @param invocation_state [Hash] the invocation state
      # @param result [Result] the invocation result
      def fire_after_invocation(invocation_state, result)
        event = Hooks::AfterInvocationEvent.new(
          agent: self,
          invocation_state: invocation_state,
          result: result
        )
        @hook_registry.fire(event)
      end
    end

    # Proxy object for direct tool invocation via agent.tool.tool_name(params).
    #
    # Fires BeforeToolCallEvent and AfterToolCallEvent hooks around each
    # tool execution to maintain consistent lifecycle behavior with the
    # event loop's tool processing.
    #
    # @example
    #   caller = Strands::Agent::ToolCaller.new(agent)
    #   caller.calculator(expr: "2 + 2")
    #
    class ToolCaller
      # @param agent [Agent] the agent whose tools to call
      def initialize(agent)
        @agent = agent
      end

      # Delegates method calls to registered tools.
      #
      # Fires BeforeToolCallEvent before execution and AfterToolCallEvent after,
      # matching the hook lifecycle of event-loop-driven tool calls.
      #
      # @param method_name [Symbol] the tool name
      # @param args [Array] positional arguments (unused)
      # @param kwargs [Hash] keyword arguments passed as tool input
      # @return [Object] the tool result
      def method_missing(method_name, *args, **kwargs)
        tool_name = method_name.to_s
        definition = @agent.tool_registry.get(tool_name)

        if definition
          tool_use = Types::Tools::ToolUse.new(
            name: tool_name,
            tool_use_id: generate_id,
            input: kwargs.empty? ? (args.first || {}) : kwargs
          )

          # Fire BeforeToolCallEvent
          before_event = Hooks::BeforeToolCallEvent.new(
            agent: @agent,
            selected_tool: definition,
            tool_use: tool_use
          )
          @agent.hook_registry.fire(before_event)

          # Check if tool call was cancelled by an intervention
          if before_event.cancel_tool
            cancel_message = before_event.cancel_tool.is_a?(String) ? before_event.cancel_tool : "Tool call denied"
            return cancel_message
          end

          # Execute the tool
          executor = Tools::Executor.new(@agent.tool_registry)
          result = nil
          exception = nil

          begin
            result = executor.execute(tool_use, agent: @agent)
          rescue StandardError => e
            exception = e
            raise
          ensure
            # Fire AfterToolCallEvent
            after_event = Hooks::AfterToolCallEvent.new(
              agent: @agent,
              selected_tool: definition,
              tool_use: tool_use,
              result: result,
              exception: exception
            )
            @agent.hook_registry.fire(after_event)
          end

          result
        else
          super
        end
      end

      # @param method_name [Symbol]
      # @param include_private [Boolean]
      # @return [Boolean]
      def respond_to_missing?(method_name, include_private = false)
        @agent.tool_registry.registered?(method_name.to_s) || super
      end

      private

      def generate_id
        require "securerandom"
        "tool_#{SecureRandom.hex(8)}"
      end
    end
  end
end
