# frozen_string_literal: true

require "rails_helper"

RSpec.describe TwilioWebhook::ProcessBookingReply do
  include Dry::Monads[:result]

  before do
    allow_any_instance_of(Whatsapp::MessageSender).to receive(:deliver).and_return(nil)
    allow(GoogleCalendarSyncJob).to receive(:perform_later)
    allow(ReminderJob).to receive(:set).and_return(double(perform_later: true))
  end

  let(:account)  { create(:account, ai_nlu_enabled: false) }
  let(:user)     { create(:user, account: account) }
  let(:service)  { create(:service, account: account, name: "Corte de cabello", price_cents: 25_000, duration_minutes: 60) }
  let(:customer) { create(:customer, account: account, phone: "+5215512345678") }
  let(:booking) do
    create(:booking, account: account, customer: customer, user: user, service: service,
                     starts_at: 2.days.from_now, status: "pending")
  end
  let(:from_phone) { "5215512345678" }

  def call(body:)
    described_class.call(
      booking:    booking,
      body:       body,
      account:    account,
      from_phone: from_phone,
      customer:   customer
    )
  end

  describe "with body '1'" do
    it "confirms the booking and sends an ack" do
      expect { call(body: "1") }.to change { booking.reload.status }.from("pending").to("confirmed")

      log = account.message_logs.outbound.order(:created_at).last
      expect(log.body).to start_with("Listo, tu cita quedó confirmada para")
    end
  end

  describe "with body '2'" do
    it "cancels the booking and sends an ack" do
      expect { call(body: "2") }.to change { booking.reload.status }.from("pending").to("cancelled")

      log = account.message_logs.outbound.order(:created_at).last
      expect(log.body).to start_with("Listo, cancelé tu cita del")
    end
  end

  describe "with free text and AI disabled" do
    it "sends a fallback message for an unrecognized body" do
      expect { call(body: "no sé") }.not_to change { booking.reload.status }

      log = account.message_logs.outbound.order(:created_at).last
      expect(log.body).to include("Tienes una cita el")
    end

    it "opens cancellation confirmation for a Spanish cancel phrase (no AI needed)" do
      expect { call(body: "Quisiera cancelar mi cita") }
        .to change(WhatsappConversation, :count).by(1)

      expect(booking.reload.status).to eq("pending")
      log = account.message_logs.outbound.order(:created_at).last
      expect(log.body).to include("¿Seguro que quieres cancelar")
    end

    it "answers appointment date question without calling the LLM" do
      expect(Llm::QuestionClassifier).not_to receive(:call)

      call(body: "cuando es mi cita")

      log = account.message_logs.outbound.order(:created_at).last
      expect(log.body).to include("Tu cita es el")
      expect(log.body).not_to include("Tienes una cita el")
    end

    it "answers address question without calling the LLM" do
      expect(Llm::QuestionClassifier).not_to receive(:call)
      account.update!(address: "Calle Falsa 123")

      call(body: "cual es la direccion")

      log = account.message_logs.outbound.order(:created_at).last
      expect(log.body).to include("Calle Falsa 123")
    end
  end

  describe "with free text and AI enabled" do
    before { account.update!(ai_nlu_enabled: true) }

    let(:base_classifier_hash) do
      { service: nil, input_tokens: 30, output_tokens: 8, model: "test-model" }
    end

    context "when the classifier returns :cancel" do
      before do
        allow(Llm::QuestionClassifier).to receive(:call).and_return(
          Success(base_classifier_hash.merge(intent: :cancel))
        )
      end

      it "creates a confirming_cancellation conversation referencing the booking" do
        expect { call(body: "Quisiera cancelar mi cita") }
          .to change(WhatsappConversation, :count).by(1)

        conversation = account.whatsapp_conversations.order(:created_at).last
        expect(conversation.step).to eq("confirming_cancellation")
        expect(conversation.booking).to eq(booking)
        expect(conversation.from_phone).to eq(from_phone)
      end

      it "sends the are-you-sure prompt" do
        call(body: "Quisiera cancelar mi cita")

        log = account.message_logs.outbound.order(:created_at).last
        expect(log.body).to start_with("¿Seguro que quieres cancelar tu cita")
        expect(log.body).to include("Responde 1 para confirmar la cancelación")
      end

      it "leaves the booking pending" do
        expect { call(body: "ya no puedo") }.not_to change { booking.reload.status }
      end
    end

    context "when the customer asks about business hours (ai disabled)" do
      it "answers with hours without calling the classifier" do
        expect(Llm::QuestionClassifier).not_to receive(:call)

        call(body: "Cual es su horario")

        log = account.message_logs.outbound.order(:created_at).last
        expect(log.body).to match(/Lunes|horarios|cerrado/i)
        expect(log.body).not_to include("Tienes una cita")
      end

      it "also matches 'cuando abren'" do
        expect(Llm::QuestionClassifier).not_to receive(:call)

        call(body: "cuando abren")

        log = account.message_logs.outbound.order(:created_at).last
        expect(log.body).to match(/Lunes|horarios|cerrado/i)
      end
    end

    context "when the customer asks about available services (ai disabled)" do
      it "answers with the services list without calling the classifier" do
        expect(Llm::QuestionClassifier).not_to receive(:call)

        call(body: "con que servicios cuentan")

        log = account.message_logs.outbound.order(:created_at).last
        expect(log.body).to include("Corte de cabello")
        expect(log.body).not_to include("Tienes una cita")
      end

      it "also matches 'que servicios tienen'" do
        expect(Llm::QuestionClassifier).not_to receive(:call)

        call(body: "que servicios tienen")

        log = account.message_logs.outbound.order(:created_at).last
        expect(log.body).to include("Corte de cabello")
      end
    end

    context "when the customer asks about the cost of their own appointment" do
      it "answers with the booked service price without calling the classifier" do
        expect(Llm::QuestionClassifier).not_to receive(:call)

        call(body: "que costo tendra mi cita")

        log = account.message_logs.outbound.order(:created_at).last
        expect(log.body).to include("Corte de cabello cuesta")
        expect(log.body).not_to include("¿Quieres reservar una cita?")
        expect(log.body).not_to include("Tienes una cita")
      end

      it "also matches 'cuanto tendre que pagar'" do
        expect(Llm::QuestionClassifier).not_to receive(:call)

        call(body: "cuanto tendre que pagar")

        log = account.message_logs.outbound.order(:created_at).last
        expect(log.body).to include("Corte de cabello cuesta")
        expect(log.body).not_to include("¿Quieres reservar una cita?")
      end

      it "does NOT short-circuit when asking about a specific service by name" do
        allow(Llm::QuestionClassifier).to receive(:call).and_return(
          Success(base_classifier_hash.merge(intent: :price, service: service))
        )

        expect(Llm::QuestionClassifier).to receive(:call)
        call(body: "¿cuánto cuesta el corte de cabello?")
      end
    end

    context "when the classifier returns a question intent" do
      before do
        allow(Llm::QuestionClassifier).to receive(:call).and_return(
          Success(base_classifier_hash.merge(intent: :price, service: service))
        )
      end

      it "answers the question without appending a CTA" do
        expect { call(body: "¿cuánto cuesta el corte?") }
          .not_to change(WhatsappConversation, :count)

        log = account.message_logs.outbound.order(:created_at).last
        expect(log.body).to include("Corte de cabello cuesta")
        expect(log.body).not_to include("¿Quieres reservar una cita?")
        expect(log.body).not_to include("Tienes una cita")
      end
    end

    context "when the classifier returns :booking" do
      before do
        allow(Llm::QuestionClassifier).to receive(:call).and_return(
          Success(base_classifier_hash.merge(intent: :booking))
        )
        # The new conversation will trigger StartConversation, which calls
        # GreetingGenerator + classifier again. Stub both to keep the test focused.
        allow(Llm::GreetingGenerator).to receive(:call).and_return(Failure(:llm_error))
      end

      it "delegates to StartConversation and creates a new conversation" do
        expect { call(body: "quiero agendar otra cita") }
          .to change(WhatsappConversation, :count).by(1)
      end
    end

    context "when the classifier returns :other" do
      before do
        allow(Llm::QuestionClassifier).to receive(:call).and_return(Failure(:not_a_question))
      end

      it "sends the fallback message" do
        call(body: "Hola")

        log = account.message_logs.outbound.order(:created_at).last
        expect(log.body).to include("Tienes una cita el")
      end
    end

    context "when the classifier raises (LLM error)" do
      before do
        allow(Llm::QuestionClassifier).to receive(:call).and_return(Failure(:llm_error))
      end

      it "sends the fallback message instead of going silent" do
        call(body: "Hola")

        log = account.message_logs.outbound.order(:created_at).last
        expect(log.body).to include("Tienes una cita el")
      end
    end

    it "stamps AI token usage on the most recent inbound MessageLog" do
      create(:message_log, account: account, customer: customer,
                           channel: "whatsapp", direction: "inbound",
                           body: "¿cuánto cuesta?", status: "delivered")

      allow(Llm::QuestionClassifier).to receive(:call).and_return(
        Success(base_classifier_hash.merge(intent: :price, service: service,
                                            input_tokens: 42, output_tokens: 11, model: "gemini"))
      )

      call(body: "¿cuánto cuesta el corte?")

      log = account.message_logs.inbound.order(:created_at).last
      expect(log.ai_input_tokens).to eq(42)
      expect(log.ai_output_tokens).to eq(11)
      expect(log.ai_model).to eq("gemini")
    end
  end
end
