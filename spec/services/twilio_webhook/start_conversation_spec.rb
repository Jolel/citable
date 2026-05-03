# frozen_string_literal: true

require "rails_helper"

RSpec.describe TwilioWebhook::StartConversation do
  include Dry::Monads[:result]

  before { allow_any_instance_of(Whatsapp::MessageSender).to receive(:deliver).and_return(nil) }

  let(:account)    { create(:account, ai_nlu_enabled: false) }
  let(:from_phone) { "5214155551234" }

  def call(customer: nil, profile_name: nil, body: nil)
    described_class.call(
      account:      account,
      from_phone:   from_phone,
      customer:     customer,
      profile_name: profile_name,
      body:         body
    )
  end

  def build_greeting_result(message = "¡Hola! Bienvenid@.")
    Success({ message: message, input_tokens: 50, output_tokens: 12,
              model: Llm::GeminiAdapter::DEFAULT_MODEL })
  end

  # ─── new customer (no name known) ──────────────────────────────────────────

  describe "new customer flow" do
    it "creates a conversation at awaiting_name" do
      result = call

      expect(result).to be_success.and(have_attributes(value!: "awaiting_name"))
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

      it "succeeds even when GreetingGenerator returns Failure (fallback path)" do
        allow(Llm::GreetingGenerator).to receive(:call).and_return(Failure(:blank_message))

        result = call

        expect(result).to be_success.and(have_attributes(value!: "awaiting_name"))
      end

      it "stamps token usage on the most recent inbound log" do
        create(:message_log, account: account, channel: "whatsapp",
               direction: "inbound", body: "hola", status: "delivered")

        allow(Llm::GreetingGenerator).to receive(:call).and_return(build_greeting_result)

        call

        log = account.message_logs.inbound.order(:created_at).last
        expect(log.ai_input_tokens).to eq(50)
        expect(log.ai_output_tokens).to eq(12)
        expect(log.ai_model).to eq(Llm::GeminiAdapter::DEFAULT_MODEL)
      end
    end
  end

  # ─── known customer ─────────────────────────────────────────────────────────

  describe "known customer flow" do
    let(:customer) { create(:customer, account: account, name: "María") }

    before { create(:service, account: account, name: "Corte de cabello") }

    it "creates a conversation at awaiting_service" do
      result = call(customer: customer)

      expect(result).to be_success.and(have_attributes(value!: "awaiting_service"))
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

        body = account.message_logs.outbound.order(:created_at).last.body
        expect(body).to start_with("¡Hola, María! 👋\n")
        expect(body).to include("1. Corte de cabello")
      end

      it "sends only the service list when GreetingGenerator returns Failure" do
        allow(Llm::GreetingGenerator).to receive(:call).and_return(Failure(:blank_message))

        call(customer: customer)

        body = account.message_logs.outbound.order(:created_at).last.body
        expect(body).to start_with("Elige un servicio:")
        expect(body).to include("1. Corte de cabello")
      end

      it "succeeds even when GreetingGenerator returns Failure (fallback path)" do
        allow(Llm::GreetingGenerator).to receive(:call).and_return(Failure(:llm_error))

        result = call(customer: customer)

        expect(result).to be_success.and(have_attributes(value!: "awaiting_service"))
      end
    end
  end

  # ─── deterministic Q&A before booking (always active) ──────────────────────

  describe "deterministic question answering (ai disabled)" do
    before do
      account.update!(ai_nlu_enabled: false)
      create(:service, account: account, name: "Corte")
    end

    it "answers a services_list question without calling any LLM" do
      expect(Llm::QuestionClassifier).not_to receive(:call)

      result = call(body: "con que servicios cuentan")

      expect(result).to be_success.and(have_attributes(value!: :answered_question))
      body = account.message_logs.outbound.order(:created_at).last.body
      expect(body).to include("Corte")
    end

    it "answers an address question without calling any LLM" do
      account.update!(address: "Av. Insurgentes 100")
      expect(Llm::QuestionClassifier).not_to receive(:call)

      result = call(body: "dónde están ubicados")

      expect(result).to be_success.and(have_attributes(value!: :answered_question))
      body = account.message_logs.outbound.order(:created_at).last.body
      expect(body).to include("Av. Insurgentes 100")
    end

    it "falls through to the booking flow for a bare greeting" do
      expect(Llm::QuestionClassifier).not_to receive(:call)

      result = call(body: "Hola")

      expect(result.value!).not_to eq(:answered_question)
      expect(account.whatsapp_conversations.count).to eq(1)
    end
  end

  # ─── question-answering branch ─────────────────────────────────────────────

  describe "question-answering branch" do
    let(:customer) { create(:customer, account: account, name: "Lucía") }

    before do
      account.update!(ai_nlu_enabled: true)
      create(:service, account: account, name: "Corte", price_cents: 25_000, duration_minutes: 60)
    end

    it "answers a question without creating a conversation when classifier returns a question intent" do
      allow(Llm::QuestionClassifier).to receive(:call).and_return(
        Success({ intent: :services_list, service: nil,
                  input_tokens: 30, output_tokens: 8, model: Llm::GeminiAdapter::DEFAULT_MODEL })
      )

      expect {
        result = call(customer: customer, body: "¿qué servicios tienen?")
        expect(result).to be_success.and(have_attributes(value!: :answered_question))
      }.not_to change { account.whatsapp_conversations.count }
    end

    it "falls through to booking flow when classifier returns Failure" do
      allow(Llm::QuestionClassifier).to receive(:call).and_return(Failure(:not_a_question))
      allow(Llm::GreetingGenerator).to receive(:call).and_return(Failure(:llm_error))

      result = call(customer: customer, body: "quiero un corte")

      expect(result).to be_success.and(have_attributes(value!: "awaiting_service"))
      expect(account.whatsapp_conversations.last.step).to eq("awaiting_service")
    end

    it "skips the classifier when ai_nlu_enabled is false" do
      account.update!(ai_nlu_enabled: false)
      expect(Llm::QuestionClassifier).not_to receive(:call)

      call(customer: customer, body: "¿qué hacen?")
    end

    it "skips the classifier when body is blank" do
      allow(Llm::GreetingGenerator).to receive(:call).and_return(Failure(:llm_error))
      expect(Llm::QuestionClassifier).not_to receive(:call)

      call(customer: customer, body: nil)
    end
  end

  # ─── profile_name path ──────────────────────────────────────────────────────

  describe "profile_name creates customer and skips awaiting_name" do
    before { create(:service, account: account, name: "Manicura") }

    it "creates the customer from profile_name and starts at awaiting_service" do
      result = call(profile_name: "Carlos")

      expect(result).to be_success.and(have_attributes(value!: "awaiting_service"))
      expect(account.customers.find_by(phone: from_phone)&.name).to eq("Carlos")
    end
  end
end
