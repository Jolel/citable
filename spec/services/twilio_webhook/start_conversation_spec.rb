# frozen_string_literal: true

require "rails_helper"

RSpec.describe TwilioWebhook::StartConversation do
  before { allow_any_instance_of(Whatsapp::MessageSender).to receive(:deliver).and_return(nil) }

  let(:account)    { create(:account, ai_nlu_enabled: false) }
  let(:from_phone) { "5214155551234" }

  def call(customer: nil, profile_name: nil)
    described_class.call(
      account:      account,
      from_phone:   from_phone,
      customer:     customer,
      profile_name: profile_name
    )
  end

  def build_greeting_result(message = "¡Hola! Bienvenid@.")
    Llm::GreetingGenerator::Result.new(
      message:       message,
      input_tokens:  50,
      output_tokens: 12,
      model:         Llm::Client::DEFAULT_MODEL
    )
  end

  # ─── new customer (no name known) ──────────────────────────────────────────

  describe "new customer flow" do
    it "creates a conversation at awaiting_name" do
      result = call

      expect(result).to be_success.and(have_attributes(value!: :awaiting_name))
      expect(account.whatsapp_conversations.last.step).to eq("awaiting_name")
    end

    context "when ai_nlu_enabled is false" do
      it "does not call GreetingGenerator" do
        expect(Llm::GreetingGenerator).not_to receive(:call)
        call
      end
    end

    context "when ai_nlu_enabled is true" do
      before { account.update!(ai_nlu_enabled: true) }

      it "calls GreetingGenerator without a customer" do
        allow(Llm::GreetingGenerator).to receive(:call).and_return(build_greeting_result)

        call

        expect(Llm::GreetingGenerator).to have_received(:call).with(
          account: account, customer: nil
        )
      end

      it "succeeds even when GreetingGenerator returns nil (fallback path)" do
        allow(Llm::GreetingGenerator).to receive(:call).and_return(nil)

        result = call

        expect(result).to be_success.and(have_attributes(value!: :awaiting_name))
      end

      it "stamps token usage on the most recent inbound log" do
        create(:message_log, account: account, channel: "whatsapp",
               direction: "inbound", body: "hola", status: "delivered")

        allow(Llm::GreetingGenerator).to receive(:call).and_return(build_greeting_result)

        call

        log = account.message_logs.inbound.order(:created_at).last
        expect(log.ai_input_tokens).to eq(50)
        expect(log.ai_output_tokens).to eq(12)
        expect(log.ai_model).to eq(Llm::Client::DEFAULT_MODEL)
      end
    end
  end

  # ─── known customer ─────────────────────────────────────────────────────────

  describe "known customer flow" do
    let(:customer) { create(:customer, account: account, name: "María") }

    before { create(:service, account: account, name: "Corte de cabello") }

    it "creates a conversation at awaiting_service" do
      result = call(customer: customer)

      expect(result).to be_success.and(have_attributes(value!: :awaiting_service))
      expect(account.whatsapp_conversations.last.step).to eq("awaiting_service")
    end

    context "when ai_nlu_enabled is false" do
      it "does not call GreetingGenerator" do
        expect(Llm::GreetingGenerator).not_to receive(:call)
        call(customer: customer)
      end
    end

    context "when ai_nlu_enabled is true" do
      before { account.update!(ai_nlu_enabled: true) }

      it "calls GreetingGenerator with the customer" do
        allow(Llm::GreetingGenerator).to receive(:call).and_return(build_greeting_result)

        call(customer: customer)

        expect(Llm::GreetingGenerator).to have_received(:call).with(
          account: account, customer: customer
        )
      end

      it "prepends the LLM intro to the Rails-formatted service list" do
        allow(Llm::GreetingGenerator).to receive(:call)
          .and_return(build_greeting_result("¡Hola, María! 👋"))

        call(customer: customer)

        # MessageSender logs the body in an outbound MessageLog on every send.
        body = account.message_logs.outbound.order(:created_at).last.body
        expect(body).to start_with("¡Hola, María! 👋\n")
        expect(body).to include("1. Corte de cabello")
      end

      it "sends only the service list when GreetingGenerator returns nil" do
        allow(Llm::GreetingGenerator).to receive(:call).and_return(nil)

        call(customer: customer)

        body = account.message_logs.outbound.order(:created_at).last.body
        expect(body).to start_with("Elige un servicio:")
        expect(body).to include("1. Corte de cabello")
      end

      it "succeeds even when GreetingGenerator returns nil (fallback path)" do
        allow(Llm::GreetingGenerator).to receive(:call).and_return(nil)

        result = call(customer: customer)

        expect(result).to be_success.and(have_attributes(value!: :awaiting_service))
      end
    end
  end

  # ─── profile_name path ──────────────────────────────────────────────────────

  describe "profile_name creates customer and skips awaiting_name" do
    before { create(:service, account: account, name: "Manicura") }

    it "creates the customer from profile_name and starts at awaiting_service" do
      result = call(profile_name: "Carlos")

      expect(result).to be_success.and(have_attributes(value!: :awaiting_service))
      expect(account.customers.find_by(phone: from_phone)&.name).to eq("Carlos")
    end
  end
end
