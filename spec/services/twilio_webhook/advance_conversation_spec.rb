# frozen_string_literal: true

require "rails_helper"

RSpec.describe TwilioWebhook::AdvanceConversation do
  include Dry::Monads[:result]

  # Suppress outbound Twilio sends and calendar syncs throughout.
  # Default QuestionClassifier stub: fall through (not a question) so that existing
  # step-handler tests are unaffected. Q&A-specific contexts override this per-example.
  before do
    allow_any_instance_of(Whatsapp::MessageSender).to receive(:deliver).and_return(nil)
    allow(GoogleCalendarSyncJob).to receive(:perform_later)
    allow(ReminderJob).to receive(:set).and_return(double(perform_later: true))
    allow(Llm::QuestionClassifier).to receive(:call).and_return(Failure(:not_a_question))
  end

  let(:account)  { create(:account, ai_nlu_enabled: false) }
  let(:user)     { create(:user, account: account) }
  let(:service)  { create(:service, account: account, name: "Corte de cabello", requires_address: false) }
  let(:customer) { create(:customer, account: account) }
  let(:conversation) do
    create(:whatsapp_conversation, account: account, customer: customer, step: "awaiting_service")
  end
  let(:from_phone) { customer.phone }

  def call(body:, step: nil)
    conversation.update!(step: step) if step
    described_class.call(conversation: conversation, body: body, account: account, from_phone: from_phone)
  end

  # ─── collect_service ────────────────────────────────────────────────────────

  describe "collect_service" do
    before { service } # ensure service exists

    context "when the customer types the numeric index" do
      it "advances to awaiting_datetime without calling the LLM" do
        expect(Llm::NluParser).not_to receive(:parse_service)
        result = call(body: "1", step: "awaiting_service")
        expect(result).to be_success
        expect(conversation.reload.step).to eq("awaiting_datetime")
      end
    end

    context "when ai_nlu_enabled is false and input is unrecognized" do
      it "re-prompts without calling the LLM" do
        expect(Llm::NluParser).not_to receive(:parse_service)
        result = call(body: "quiero un corte", step: "awaiting_service")
        expect(result).to be_success.and(have_attributes(value!: :awaiting_service))
        expect(conversation.reload.step).to eq("awaiting_service")
      end
    end

    context "when ai_nlu_enabled is true and input is free text" do
      before { account.update!(ai_nlu_enabled: true) }

      let(:nlu_success) do
        Success({ value: service, input_tokens: 80, output_tokens: 15,
                  model: Llm::GeminiAdapter::DEFAULT_MODEL })
      end

      it "calls the NLU parser and advances to awaiting_datetime" do
        allow(Llm::NluParser).to receive(:parse_service).and_return(nlu_success)

        result = call(body: "quiero un corte", step: "awaiting_service")

        expect(result).to be_success
        expect(conversation.reload.step).to eq("awaiting_datetime")
        expect(conversation.reload.service).to eq(service)
      end

      it "records AI token usage on the most recent inbound MessageLog" do
        create(:message_log, account: account, customer: customer,
               channel: "whatsapp", direction: "inbound", body: "quiero un corte", status: "delivered")

        allow(Llm::NluParser).to receive(:parse_service).and_return(nlu_success)
        call(body: "quiero un corte", step: "awaiting_service")

        log = account.message_logs.inbound.order(:created_at).last
        expect(log.ai_input_tokens).to eq(80)
        expect(log.ai_output_tokens).to eq(15)
        expect(log.ai_model).to eq(Llm::GeminiAdapter::DEFAULT_MODEL)
      end

      context "when the NLU parser returns Failure (low confidence / error)" do
        it "re-prompts without advancing" do
          allow(Llm::NluParser).to receive(:parse_service).and_return(Failure(:low_confidence))

          result = call(body: "no sé qué quiero", step: "awaiting_service")

          expect(result).to be_success.and(have_attributes(value!: :awaiting_service))
          expect(conversation.reload.step).to eq("awaiting_service")
        end
      end
    end
  end

  # ─── collect_datetime ───────────────────────────────────────────────────────

  describe "collect_datetime" do
    before { conversation.update!(step: "awaiting_datetime", service: service) }

    context "when the customer uses a strict format" do
      it "advances without calling the LLM" do
        expect(Llm::NluParser).not_to receive(:parse_datetime)
        result = call(body: "2026-05-10 15:00", step: "awaiting_datetime")
        expect(result).to be_success
        expect(conversation.reload.step).to eq("confirming_booking")
      end
    end

    context "when ai_nlu_enabled is false and format is unrecognized" do
      it "re-prompts without calling the LLM" do
        expect(Llm::NluParser).not_to receive(:parse_datetime)
        result = call(body: "viernes a las 3", step: "awaiting_datetime")
        expect(result).to be_success.and(have_attributes(value!: :awaiting_datetime))
      end
    end

    context "when ai_nlu_enabled is true and input is free-text Spanish" do
      before { account.update!(ai_nlu_enabled: true) }

      let(:parsed_time) { Time.zone.parse("2026-05-01T15:00:00") }
      let(:nlu_success) do
        Success({ value: parsed_time, input_tokens: 95, output_tokens: 18,
                  model: Llm::GeminiAdapter::DEFAULT_MODEL })
      end

      it "calls the NLU parser and advances to confirming_booking" do
        allow(Llm::NluParser).to receive(:parse_datetime).and_return(nlu_success)

        result = call(body: "viernes a las 3", step: "awaiting_datetime")

        expect(result).to be_success
        expect(conversation.reload.step).to eq("confirming_booking")
        expect(conversation.reload.requested_starts_at).to be_within(1.second).of(parsed_time)
      end

      context "when the NLU parser returns Failure" do
        it "re-prompts without advancing" do
          allow(Llm::NluParser).to receive(:parse_datetime).and_return(Failure(:low_confidence))

          result = call(body: "no sé cuándo", step: "awaiting_datetime")

          expect(result).to be_success.and(have_attributes(value!: :awaiting_datetime))
          expect(conversation.reload.step).to eq("awaiting_datetime")
        end
      end
    end
  end

  # ─── confirm_booking ────────────────────────────────────────────────────────

  describe "confirm_booking" do
    before do
      user  # ensure a staff member exists for create_booking
      conversation.update!(
        step:               "confirming_booking",
        service:            service,
        requested_starts_at: 1.day.from_now
      )
    end

    it "creates a booking and completes the conversation when body is '1'" do
      expect(Llm::NluParser).not_to receive(:parse_confirmation)

      result = call(body: "1", step: "confirming_booking")

      expect(result).to be_success
      expect(result.value!).to be_a(Booking)
      expect(conversation.reload.step).to eq("completed")
    end

    it "cancels the conversation when body is '2'" do
      expect(Llm::NluParser).not_to receive(:parse_confirmation)

      result = call(body: "2", step: "confirming_booking")

      expect(result).to be_success.and(have_attributes(value!: :cancelled))
      expect(conversation.reload.step).to eq("cancelled")
    end

    context "when ai_nlu_enabled is false and body is unrecognized" do
      it "re-prompts without calling the LLM" do
        expect(Llm::NluParser).not_to receive(:parse_confirmation)

        result = call(body: "dale", step: "confirming_booking")

        expect(result).to be_success.and(have_attributes(value!: :confirming_booking))
        expect(conversation.reload.step).to eq("confirming_booking")
      end
    end

    context "when ai_nlu_enabled is true" do
      before { account.update!(ai_nlu_enabled: true) }

      let(:confirmed_nlu) do
        Success({ value: :confirmed, input_tokens: 60, output_tokens: 10,
                  model: Llm::GeminiAdapter::DEFAULT_MODEL })
      end

      let(:cancelled_nlu) do
        Success({ value: :cancelled, input_tokens: 60, output_tokens: 10,
                  model: Llm::GeminiAdapter::DEFAULT_MODEL })
      end

      it "creates a booking when the NLU parser returns :confirmed" do
        allow(Llm::NluParser).to receive(:parse_confirmation).and_return(confirmed_nlu)

        result = call(body: "dale", step: "confirming_booking")

        expect(result).to be_success
        expect(result.value!).to be_a(Booking)
        expect(conversation.reload.step).to eq("completed")
      end

      it "cancels when the NLU parser returns :cancelled" do
        allow(Llm::NluParser).to receive(:parse_confirmation).and_return(cancelled_nlu)

        result = call(body: "mejor no", step: "confirming_booking")

        expect(result).to be_success.and(have_attributes(value!: :cancelled))
        expect(conversation.reload.step).to eq("cancelled")
      end

      it "re-prompts when the NLU parser returns Failure (uncertain input)" do
        allow(Llm::NluParser).to receive(:parse_confirmation).and_return(Failure(:low_confidence))

        result = call(body: "¿cómo?", step: "confirming_booking")

        expect(result).to be_success.and(have_attributes(value!: :confirming_booking))
        expect(conversation.reload.step).to eq("confirming_booking")
      end

      it "does not call the LLM when body is already '1' or '2'" do
        expect(Llm::NluParser).not_to receive(:parse_confirmation)

        call(body: "1", step: "confirming_booking")
      end
    end
  end

  # ─── confirm_cancellation ──────────────────────────────────────────────────

  describe "confirm_cancellation" do
    let(:existing_booking) do
      create(:booking, account: account, customer: customer, user: user, service: service,
                       starts_at: 2.days.from_now, status: "pending")
    end

    before do
      conversation.update!(step: "confirming_cancellation", booking: existing_booking)
    end

    it "cancels the booking when body is '1'" do
      expect(Llm::NluParser).not_to receive(:parse_confirmation)

      result = call(body: "1", step: "confirming_cancellation")

      expect(result).to be_success.and(have_attributes(value!: :cancelled_booking))
      expect(existing_booking.reload).to be_cancelled
      expect(conversation.reload.step).to eq("completed")
    end

    it "keeps the booking when body is '2'" do
      result = call(body: "2", step: "confirming_cancellation")

      expect(result).to be_success.and(have_attributes(value!: :kept_booking))
      expect(existing_booking.reload).to be_pending
      expect(conversation.reload.step).to eq("completed")
    end

    context "when ai_nlu_enabled is true" do
      before { account.update!(ai_nlu_enabled: true) }

      it "cancels when NLU returns :confirmed" do
        allow(Llm::NluParser).to receive(:parse_confirmation).and_return(
          Success({ value: :confirmed, input_tokens: 50, output_tokens: 8, model: "test" })
        )

        result = call(body: "sí", step: "confirming_cancellation")

        expect(result).to be_success.and(have_attributes(value!: :cancelled_booking))
        expect(existing_booking.reload).to be_cancelled
      end

      it "re-prompts when NLU is unsure" do
        allow(Llm::NluParser).to receive(:parse_confirmation).and_return(Failure(:low_confidence))

        result = call(body: "tal vez", step: "confirming_cancellation")

        expect(result).to be_success.and(have_attributes(value!: :confirming_cancellation))
        expect(conversation.reload.step).to eq("confirming_cancellation")
        expect(existing_booking.reload).to be_pending
      end
    end

    context "when the conversation has no booking attached" do
      before { conversation.update!(booking: nil) }

      it "returns Failure(:missing_booking)" do
        result = call(body: "1", step: "confirming_cancellation")

        expect(result).to be_failure.and(have_attributes(failure: :missing_booking))
      end
    end
  end

  # ─── deterministic mid-flow Q&A (always active) ─────────────────────────────

  describe "deterministic question answering (ai disabled)" do
    before do
      service
      account.update!(ai_nlu_enabled: false)
      conversation.update!(step: "awaiting_service")
    end

    it "answers a services_list question without calling any LLM" do
      expect(Llm::QuestionClassifier).not_to receive(:call)

      result = call(body: "con que servicios cuentan")

      expect(result).to be_success.and(have_attributes(value!: :answered_question))
      expect(conversation.reload.step).to eq("awaiting_service")
      body = account.message_logs.outbound.order(:created_at).last.body
      expect(body).to include(service.name)
    end

    it "answers a hours question without calling any LLM" do
      expect(Llm::QuestionClassifier).not_to receive(:call)

      result = call(body: "cual es su horario")

      expect(result).to be_success.and(have_attributes(value!: :answered_question))
      body = account.message_logs.outbound.order(:created_at).last.body
      expect(body).to match(/horario|Lunes|cerrado/i)
    end
  end

  describe "greeting mid-flow" do
    before do
      service
      conversation.update!(step: "awaiting_service")
    end

    it "re-sends the current step prompt and does not advance" do
      expect(Llm::QuestionClassifier).not_to receive(:call)

      result = call(body: "Hola")

      expect(result).to be_success.and(have_attributes(value!: :greeted))
      expect(conversation.reload.step).to eq("awaiting_service")
      body = account.message_logs.outbound.order(:created_at).last.body
      expect(body).to include("Elige un servicio")
    end

    it "does not treat 'Hola quiero un corte' as a greeting" do
      result = call(body: "Hola quiero un corte")

      expect(result.value!).not_to eq(:greeted)
    end
  end

  # ─── mid-booking question answering ─────────────────────────────────────────

  describe "mid-booking question answering" do
    before do
      service  # ensure the service exists
      account.update!(ai_nlu_enabled: true)
    end

    let(:question_result) do
      Success({
        intent: :price, service: service,
        input_tokens: 70, output_tokens: 12,
        model: Llm::GeminiAdapter::DEFAULT_MODEL
      })
    end

    shared_examples "answers question and re-prompts current step" do |step|
      before { conversation.update!(step: step, service: service, requested_starts_at: 1.day.from_now) }

      it "returns Success(:answered_question) and does not advance the step" do
        allow(Llm::QuestionClassifier).to receive(:call).and_return(question_result)
        allow(TwilioWebhook::AnswerQuestion).to receive(:call).and_return("Corte de cabello cuesta $200.00 MXN y dura 30 min.\n\n¿Quieres reservar una cita?")

        result = call(body: "¿cuánto cuesta el corte?", step: step)

        expect(result).to be_success.and(have_attributes(value!: :answered_question))
        expect(conversation.reload.step).to eq(step)
      end

      it "sends answer + re-prompt as a single outbound message" do
        allow(Llm::QuestionClassifier).to receive(:call).and_return(question_result)
        allow(TwilioWebhook::AnswerQuestion).to receive(:call).and_return("La respuesta.\n\nElige un servicio:\n1. Corte de cabello (30 min)")

        expect(Whatsapp::MessageSender).to receive(:call).once
        call(body: "¿cuánto cuesta?", step: step)
      end
    end

    include_examples "answers question and re-prompts current step", "awaiting_service"
    include_examples "answers question and re-prompts current step", "awaiting_datetime"
    include_examples "answers question and re-prompts current step", "confirming_booking"

    context "when ai_nlu_enabled is false" do
      before do
        account.update!(ai_nlu_enabled: false)
        conversation.update!(step: "awaiting_service")
      end

      it "does not call QuestionClassifier and falls through to the step handler" do
        expect(Llm::QuestionClassifier).not_to receive(:call)

        result = call(body: "¿cuánto cuesta el corte?", step: "awaiting_service")

        expect(result).to be_success.and(have_attributes(value!: :awaiting_service))
        expect(conversation.reload.step).to eq("awaiting_service")
      end
    end

    context "when the classifier returns a booking or other intent" do
      before { conversation.update!(step: "awaiting_service") }

      it "falls through to the normal service-collection handler" do
        non_question = Success({
          intent: :booking, service: nil,
          input_tokens: 50, output_tokens: 8,
          model: Llm::GeminiAdapter::DEFAULT_MODEL
        })
        allow(Llm::QuestionClassifier).to receive(:call).and_return(non_question)
        allow(Llm::NluParser).to receive(:parse_service).and_return(Success({ value: service, input_tokens: 80, output_tokens: 15, model: Llm::GeminiAdapter::DEFAULT_MODEL }))

        result = call(body: "quiero reservar un corte", step: "awaiting_service")

        expect(result).to be_success
        expect(conversation.reload.step).to eq("awaiting_datetime")
      end
    end

    context "when the classifier returns Failure" do
      before { conversation.update!(step: "awaiting_service") }

      it "falls through to the normal step handler" do
        allow(Llm::QuestionClassifier).to receive(:call).and_return(Failure(:llm_error))
        allow(Llm::NluParser).to receive(:parse_service).and_return(Failure(:low_confidence))

        result = call(body: "algo raro", step: "awaiting_service")

        expect(result).to be_success.and(have_attributes(value!: :awaiting_service))
        expect(conversation.reload.step).to eq("awaiting_service")
      end
    end

    context "when body is '1' or '2'" do
      before { conversation.update!(step: "confirming_booking", service: service, requested_starts_at: 1.day.from_now) }

      it "skips QuestionClassifier entirely for '1'" do
        expect(Llm::QuestionClassifier).not_to receive(:call)

        user  # ensure staff exists
        result = call(body: "1", step: "confirming_booking")

        expect(result).to be_success
        expect(result.value!).to be_a(Booking)
      end

      it "skips QuestionClassifier entirely for '2'" do
        expect(Llm::QuestionClassifier).not_to receive(:call)

        result = call(body: "2", step: "confirming_booking")

        expect(result).to be_success.and(have_attributes(value!: :cancelled))
      end
    end
  end
end
