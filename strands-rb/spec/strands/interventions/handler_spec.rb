# frozen_string_literal: true

require "spec_helper"

RSpec.describe Strands::Interventions::Handler do
  let(:agent) { double("agent") }

  describe "abstract interface" do
    it "raises NotImplementedError for #name" do
      handler = described_class.new
      expect { handler.name }.to raise_error(NotImplementedError)
    end
  end

  describe "default lifecycle methods" do
    let(:handler) { described_class.new }

    it "#before_invocation returns Proceed" do
      result = handler.before_invocation(nil)
      expect(result).to be_a(Strands::Interventions::Proceed)
    end

    it "#before_tool_call returns Proceed" do
      result = handler.before_tool_call(nil)
      expect(result).to be_a(Strands::Interventions::Proceed)
    end

    it "#after_tool_call returns Proceed" do
      result = handler.after_tool_call(nil)
      expect(result).to be_a(Strands::Interventions::Proceed)
    end

    it "#before_model_call returns Proceed" do
      result = handler.before_model_call(nil)
      expect(result).to be_a(Strands::Interventions::Proceed)
    end

    it "#after_model_call returns Proceed" do
      result = handler.after_model_call(nil)
      expect(result).to be_a(Strands::Interventions::Proceed)
    end
  end

  describe "#on_error" do
    it "defaults to :throw" do
      handler = described_class.new
      expect(handler.on_error).to eq(:throw)
    end
  end

  describe "custom handler" do
    let(:custom_handler_class) do
      Class.new(described_class) do
        def name
          "custom-handler"
        end

        def before_tool_call(event)
          Strands::Interventions::Deny.new(reason: "blocked")
        end
      end
    end

    it "can override lifecycle methods" do
      handler = custom_handler_class.new
      expect(handler.name).to eq("custom-handler")

      event = Strands::Hooks::BeforeToolCallEvent.new(
        agent: agent, selected_tool: nil, tool_use: {}
      )
      result = handler.before_tool_call(event)
      expect(result).to be_a(Strands::Interventions::Deny)
      expect(result.reason).to eq("blocked")
    end

    it "non-overridden methods still return Proceed" do
      handler = custom_handler_class.new
      expect(handler.before_model_call(nil)).to be_a(Strands::Interventions::Proceed)
    end
  end

  describe "handler returning Guide" do
    let(:guiding_handler_class) do
      Class.new(described_class) do
        def name
          "guiding-handler"
        end

        def before_invocation(event)
          Strands::Interventions::Guide.new(feedback: "please reconsider")
        end
      end
    end

    it "returns Guide with feedback" do
      handler = guiding_handler_class.new
      result = handler.before_invocation(nil)
      expect(result).to be_a(Strands::Interventions::Guide)
      expect(result.feedback).to eq("please reconsider")
    end
  end

  describe "handler returning Transform" do
    let(:transform_handler_class) do
      Class.new(described_class) do
        def name
          "transform-handler"
        end

        def before_tool_call(event)
          Strands::Interventions::Transform.new(
            apply: ->(e) { e.tool_use = { name: "modified" } },
            reason: "modification needed"
          )
        end
      end
    end

    it "returns Transform with apply callable" do
      handler = transform_handler_class.new
      event = Strands::Hooks::BeforeToolCallEvent.new(
        agent: agent, selected_tool: nil, tool_use: { name: "original" }
      )
      result = handler.before_tool_call(event)
      expect(result).to be_a(Strands::Interventions::Transform)

      result.apply.call(event)
      expect(event.tool_use).to eq({ name: "modified" })
    end
  end
end
