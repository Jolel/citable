# frozen_string_literal: true

require "rails_helper"

RSpec.describe TwilioWebhook::AdvanceConversation do
  include Dry::Monads[:result]

  # Suppress outbound Twilio sends and calendar syncs throughout.
  # Default stubs:
  #   - QuestionClassifier → fall through (not a question)
  #   - BookingSlotExtractor → Failure so NLU tests must opt-in explicitly
  before do
    allow_any_instance_of(Whatsapp::MessageSender).to receive(:deliver).and_return(nil)
    allow(GoogleCalendarSyncJob).to receive(:perform_later)
    allow(ReminderJob).to receive(:set).and_return(double(perform_later: true))
    allow(Llm::QuestionClassifier).to receive(:call).and_return(Failure(:not_a_question))
    allow(Llm::BookingSlotExtractor).to receive(:call).and_return(Failure(:llm_error))
    allow(Llm::ScopeClassifier).to receive(:call).and_return(Failure(:not_out_of_scope))
    allow(TwilioWebhook::CorrectionDetector).to receive(:call).and_return(Failure(:no_correction))
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
      it "advances to awaiting_datetime without calling the extractor" do
        expect(Llm::BookingSlotExtractor).not_to receive(:call)
        result = call(body: "1", step: "awaiting_service")
        expect(result).to be_success
        expect(conversation.reload.step).to eq("awaiting_datetime")
      end
    end

    context "when ai_nlu_enabled is false and input is unrecognized" do
      it "re-prompts without calling the extractor" do
        expect(Llm::BookingSlotExtractor).not_to receive(:call)
        result = call(body: "quiero un corte", step: "awaiting_service")
        expect(result).to be_success.and(have_attributes(value!: :awaiting_service))
        expect(conversation.reload.step).to eq("awaiting_service")
      end
    end

    context "when ai_nlu_enabled is true and input is free text" do
      before { account.update!(ai_nlu_enabled: true) }

      def extractor_service_only
        Success({
          slots:          { service: service, starts_at: nil, address: nil, confirmation: nil },
          confidences:    { service: 0.92, datetime: 0.0, address: 0.0, confirmation: 0.0 },
          top_candidates: [],
          input_tokens:   80,
          output_tokens:  15,
          model:          Llm::GeminiAdapter::DEFAULT_MODEL
        })
      end

      it "calls the slot extractor and advances to awaiting_datetime" do
        allow(Llm::BookingSlotExtractor).to receive(:call).and_return(extractor_service_only)

        result = call(body: "quiero un corte", step: "awaiting_service")

        expect(result).to be_success
        expect(conversation.reload.step).to eq("awaiting_datetime")
        expect(conversation.reload.service).to eq(service)
      end

      it "records AI token usage on the most recent inbound MessageLog" do
        create(:message_log, account: account, customer: customer,
               channel: "whatsapp", direction: "inbound", body: "quiero un corte", status: "delivered")

        allow(Llm::BookingSlotExtractor).to receive(:call).and_return(extractor_service_only)
        call(body: "quiero un corte", step: "awaiting_service")

        log = account.message_logs.inbound.order(:created_at).last
        expect(log.ai_input_tokens).to eq(80)
        expect(log.ai_output_tokens).to eq(15)
        expect(log.ai_model).to eq(Llm::GeminiAdapter::DEFAULT_MODEL)
      end

      context "when the extractor returns Failure (low confidence / LLM error)" do
        it "re-prompts without advancing" do
          allow(Llm::BookingSlotExtractor).to receive(:call).and_return(Failure(:llm_error))

          result = call(body: "no sé qué quiero", step: "awaiting_service")

          expect(result).to be_success.and(have_attributes(value!: :awaiting_service))
          expect(conversation.reload.step).to eq("awaiting_service")
        end
      end

      context "when the message includes both service and datetime (multi-slot skip-ahead)" do
        let(:parsed_time) { Time.zone.parse("2026-05-09T15:00:00") }

        def extractor_multi_slot
          Success({
            slots:          { service: service, starts_at: parsed_time, address: nil, confirmation: nil },
            confidences:    { service: 0.9, datetime: 0.88, address: 0.0, confirmation: 0.0 },
            top_candidates: [],
            input_tokens:   95,
            output_tokens:  20,
            model:          Llm::GeminiAdapter::DEFAULT_MODEL
          })
        end

        it "skips awaiting_datetime and advances directly to confirming_booking" do
          allow(Llm::BookingSlotExtractor).to receive(:call).and_return(extractor_multi_slot)

          result = call(body: "quiero un corte el viernes a las 3", step: "awaiting_service")

          expect(result).to be_success
          expect(conversation.reload.step).to eq("confirming_booking")
          expect(conversation.reload.service).to eq(service)
          expect(conversation.reload.requested_starts_at).to be_within(1.second).of(parsed_time)
        end

        it "only makes one LLM call for the turn" do
          expect(Llm::BookingSlotExtractor).to receive(:call).once.and_return(extractor_multi_slot)
          call(body: "quiero un corte el viernes a las 3", step: "awaiting_service")
        end
      end
    end
  end

  # ─── disambiguation ─────────────────────────────────────────────────────────

  describe "disambiguation" do
    let(:service_b) { create(:service, account: account, name: "Corte fade", requires_address: false) }

    before do
      service   # Corte de cabello
      service_b # Corte fade
      account.update!(ai_nlu_enabled: true)
      conversation.update!(step: "awaiting_service")
    end

    def extractor_with_candidates(primary_service: nil)
      Success({
        slots:          { service: primary_service, starts_at: nil, address: nil, confirmation: nil },
        confidences:    { service: primary_service ? 0.85 : 0.0, datetime: 0.0, address: 0.0, confirmation: 0.0 },
        top_candidates: [ service, service_b ],
        input_tokens:   80,
        output_tokens:  14,
        model:          Llm::GeminiAdapter::DEFAULT_MODEL
      })
    end

    def extractor_no_match
      Success({
        slots:          { service: nil, starts_at: nil, address: nil, confirmation: nil },
        confidences:    { service: 0.0, datetime: 0.0, address: 0.0, confirmation: 0.0 },
        top_candidates: [],
        input_tokens:   70,
        output_tokens:  10,
        model:          Llm::GeminiAdapter::DEFAULT_MODEL
      })
    end

    context "when extractor returns medium-confidence candidates and no primary service" do
      it "advances to awaiting_disambiguation and sends a targeted question" do
        allow(Llm::BookingSlotExtractor).to receive(:call).and_return(extractor_with_candidates)

        result = call(body: "un corte", step: "awaiting_service")

        expect(result).to be_success.and(have_attributes(value!: :awaiting_disambiguation))
        expect(conversation.reload.step).to eq("awaiting_disambiguation")
        meta = conversation.reload.metadata["disambiguation"]
        expect(meta["slot"]).to eq("service")
        expect(meta["candidates"]).to contain_exactly(service.id, service_b.id)
      end

      it "sends a disambiguation message listing the candidate services" do
        allow(Llm::BookingSlotExtractor).to receive(:call).and_return(extractor_with_candidates)

        call(body: "un corte", step: "awaiting_service")

        body_sent = account.message_logs.outbound.order(:created_at).last.body
        expect(body_sent).to include(service.name)
        expect(body_sent).to include(service_b.name)
      end
    end

    context "when at awaiting_disambiguation and customer types a digit" do
      before do
        conversation.update!(
          step:     "awaiting_disambiguation",
          metadata: { "disambiguation" => { "slot" => "service", "candidates" => [ service.id, service_b.id ] } }
        )
      end

      it "resolves '1' to the first candidate and advances to awaiting_datetime" do
        result = call(body: "1", step: "awaiting_disambiguation")

        expect(result).to be_success.and(have_attributes(value!: :awaiting_datetime))
        expect(conversation.reload.step).to eq("awaiting_datetime")
        expect(conversation.reload.service).to eq(service)
        expect(conversation.reload.metadata["disambiguation"]).to be_nil
      end

      it "resolves '2' to the second candidate and advances to awaiting_datetime" do
        result = call(body: "2", step: "awaiting_disambiguation")

        expect(result).to be_success.and(have_attributes(value!: :awaiting_datetime))
        expect(conversation.reload.service).to eq(service_b)
      end
    end

    context "when at awaiting_disambiguation and LLM re-extraction resolves to a candidate" do
      before do
        conversation.update!(
          step:     "awaiting_disambiguation",
          metadata: { "disambiguation" => { "slot" => "service", "candidates" => [ service.id, service_b.id ] } }
        )
        allow(Llm::BookingSlotExtractor).to receive(:call).and_return(
          Success({
            slots:          { service: service_b, starts_at: nil, address: nil, confirmation: nil },
            confidences:    { service: 0.9, datetime: 0.0, address: 0.0, confirmation: 0.0 },
            top_candidates: [],
            input_tokens:   80,
            output_tokens:  12,
            model:          Llm::GeminiAdapter::DEFAULT_MODEL
          })
        )
      end

      it "resolves to the matched candidate and advances to awaiting_datetime" do
        result = call(body: "el fade", step: "awaiting_disambiguation")

        expect(result).to be_success.and(have_attributes(value!: :awaiting_datetime))
        expect(conversation.reload.service).to eq(service_b)
      end
    end

    context "when at awaiting_disambiguation and the user is still ambiguous" do
      before do
        conversation.update!(
          step:     "awaiting_disambiguation",
          metadata: { "disambiguation" => { "slot" => "service", "candidates" => [ service.id, service_b.id ] } }
        )
        allow(Llm::BookingSlotExtractor).to receive(:call).and_return(extractor_no_match)
      end

      it "falls back to the full service list and resets to awaiting_service" do
        result = call(body: "no sé", step: "awaiting_disambiguation")

        expect(result).to be_success.and(have_attributes(value!: :awaiting_service))
        expect(conversation.reload.step).to eq("awaiting_service")
        expect(conversation.reload.metadata["disambiguation"]).to be_nil
      end
    end

    context "Mexican-Spanish affirmative variants in confirm_booking (via NLU)" do
      let(:confirmed_nlu) do
        Success({ value: :confirmed, input_tokens: 60, output_tokens: 10,
                  model: Llm::GeminiAdapter::DEFAULT_MODEL })
      end

      before do
        user  # ensure a staff member exists
        account.update!(ai_nlu_enabled: true)
        conversation.update!(
          step:                "confirming_booking",
          service:             service,
          requested_starts_at: 1.day.from_now
        )
        allow(Llm::NluParser).to receive(:parse_confirmation).and_return(confirmed_nlu)
      end

      %w[simón obvio sale].each do |word|
        it "confirms booking when body is '#{word}'" do
          result = call(body: word, step: "confirming_booking")

          expect(result).to be_success
          expect(result.value!).to be_a(Booking)
          expect(conversation.reload.step).to eq("completed")
        end
      end
    end

    context "Mexican-Spanish negative variants in confirm_booking (via NLU)" do
      let(:cancelled_nlu) do
        Success({ value: :cancelled, input_tokens: 60, output_tokens: 10,
                  model: Llm::GeminiAdapter::DEFAULT_MODEL })
      end

      before do
        account.update!(ai_nlu_enabled: true)
        conversation.update!(
          step:                "confirming_booking",
          service:             service,
          requested_starts_at: 1.day.from_now
        )
        allow(Llm::NluParser).to receive(:parse_confirmation).and_return(cancelled_nlu)
      end

      %w[nones].each do |word|
        it "cancels booking when body is '#{word}'" do
          result = call(body: word, step: "confirming_booking")

          expect(result).to be_success.and(have_attributes(value!: :cancelled))
          expect(conversation.reload.step).to eq("cancelled")
        end
      end
    end
  end

  # ─── collect_datetime ───────────────────────────────────────────────────────

  describe "collect_datetime" do
    before { conversation.update!(step: "awaiting_datetime", service: service) }

    context "when ai_nlu_enabled is false" do
      it "re-prompts without calling the extractor" do
        expect(Llm::BookingSlotExtractor).not_to receive(:call)
        result = call(body: "viernes a las 3", step: "awaiting_datetime")
        expect(result).to be_success.and(have_attributes(value!: :awaiting_datetime))
      end
    end

    context "when ai_nlu_enabled is true and input is free-text Spanish" do
      before { account.update!(ai_nlu_enabled: true) }

      let(:parsed_time) { Time.zone.parse("2026-05-09T15:00:00") }

      def extractor_datetime_only
        Success({
          slots:          { service: nil, starts_at: parsed_time, address: nil, confirmation: nil },
          confidences:    { service: 0.0, datetime: 0.9, address: 0.0, confirmation: 0.0 },
          top_candidates: [],
          input_tokens:   95,
          output_tokens:  18,
          model:          Llm::GeminiAdapter::DEFAULT_MODEL
        })
      end

      it "calls the slot extractor and advances to confirming_booking" do
        allow(Llm::BookingSlotExtractor).to receive(:call).and_return(extractor_datetime_only)

        result = call(body: "el viernes a las 3", step: "awaiting_datetime")

        expect(result).to be_success
        expect(conversation.reload.step).to eq("confirming_booking")
        expect(conversation.reload.requested_starts_at).to be_within(1.second).of(parsed_time)
      end

      context "when the extractor returns Failure" do
        it "re-prompts without advancing" do
          allow(Llm::BookingSlotExtractor).to receive(:call).and_return(Failure(:llm_error))

          result = call(body: "no sé cuándo", step: "awaiting_datetime")

          expect(result).to be_success.and(have_attributes(value!: :awaiting_datetime))
          expect(conversation.reload.step).to eq("awaiting_datetime")
        end
      end

      context "when the extractor returns success but starts_at is nil (partial expression)" do
        it "re-prompts — only date provided, no time" do
          no_time = Success({
            slots:          { service: nil, starts_at: nil, address: nil, confirmation: nil },
            confidences:    { service: 0.0, datetime: 0.3, address: 0.0, confirmation: 0.0 },
            top_candidates: [],
            input_tokens:   80,
            output_tokens:  12,
            model:          Llm::GeminiAdapter::DEFAULT_MODEL
          })
          allow(Llm::BookingSlotExtractor).to receive(:call).and_return(no_time)

          result = call(body: "el viernes", step: "awaiting_datetime")

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

        result = call(body: "quizás", step: "confirming_booking")

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
        extractor_result = Success({
          slots:          { service: service, starts_at: nil, address: nil, confirmation: nil },
          confidences:    { service: 0.9, datetime: 0.0, address: 0.0, confirmation: 0.0 },
          top_candidates: [],
          input_tokens:   80, output_tokens: 15, model: Llm::GeminiAdapter::DEFAULT_MODEL
        })
        allow(Llm::QuestionClassifier).to receive(:call).and_return(non_question)
        allow(Llm::BookingSlotExtractor).to receive(:call).and_return(extractor_result)

        result = call(body: "quiero reservar un corte", step: "awaiting_service")

        expect(result).to be_success
        expect(conversation.reload.step).to eq("awaiting_datetime")
      end
    end

    context "when the classifier returns Failure" do
      before { conversation.update!(step: "awaiting_service") }

      it "falls through to the normal step handler" do
        allow(Llm::QuestionClassifier).to receive(:call).and_return(Failure(:llm_error))
        allow(Llm::BookingSlotExtractor).to receive(:call).and_return(Failure(:llm_error))

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

  # ─── mid-flow corrections ────────────────────────────────────────────────────

  describe "mid-flow corrections" do
    let(:locked_time) { Time.zone.parse("2026-05-09T15:00:00") }
    let(:new_time)    { Time.zone.parse("2026-05-10T17:00:00") }

    before do
      service
      account.update!(ai_nlu_enabled: true)
      conversation.update!(
        step:                "confirming_booking",
        service:             service,
        requested_starts_at: locked_time
      )
    end

    def correction_success(rewound_to:, applied_slots: [ :starts_at ])
      Success({
        rewound_to:    rewound_to,
        applied_slots: applied_slots,
        input_tokens:  90,
        output_tokens: 16,
        model:         "test"
      })
    end

    it "returns Success(:corrected) and re-prompts the rewound step" do
      conversation.update!(requested_starts_at: new_time)
      allow(TwilioWebhook::CorrectionDetector).to receive(:call)
        .and_return(correction_success(rewound_to: "confirming_booking"))

      result = call(body: "mejor el sábado a las 5", step: "confirming_booking")

      expect(result).to be_success.and(have_attributes(value!: :corrected))
    end

    it "sends a confirmation prompt when rewound to confirming_booking" do
      conversation.update!(requested_starts_at: new_time)
      allow(TwilioWebhook::CorrectionDetector).to receive(:call)
        .and_return(correction_success(rewound_to: "confirming_booking"))

      expect(Whatsapp::MessageSender).to receive(:call).once

      call(body: "mejor el sábado a las 5", step: "confirming_booking")
    end

    it "does not call CorrectionDetector when ai_nlu_enabled is false" do
      account.update!(ai_nlu_enabled: false)
      expect(TwilioWebhook::CorrectionDetector).not_to receive(:call)

      call(body: "mejor el sábado a las 5", step: "confirming_booking")
    end

    it "does not call CorrectionDetector for digit inputs" do
      expect(TwilioWebhook::CorrectionDetector).not_to receive(:call)

      user
      call(body: "1", step: "confirming_booking")
    end

    it "falls through to normal step processing when CorrectionDetector returns Failure" do
      allow(TwilioWebhook::CorrectionDetector).to receive(:call)
        .and_return(Failure(:nothing_changed))
      allow(Llm::NluParser).to receive(:parse_confirmation)
        .and_return(Failure(:low_confidence))

      result = call(body: "mejor sí confirmado", step: "confirming_booking")

      # Falls through to confirm_booking; body is ambiguous → re-prompts
      expect(result).to be_success.and(have_attributes(value!: :confirming_booking))
      expect(conversation.reload.step).to eq("confirming_booking")
    end
  end

  # ─── out-of-scope FAQ handling ───────────────────────────────────────────────

  describe "out-of-scope FAQ handling" do
    before do
      service
      account.update!(ai_nlu_enabled: true)
      conversation.update!(step: "awaiting_service")
    end

    context "when QuestionClassifier returns :out_of_scope" do
      before do
        allow(Llm::QuestionClassifier).to receive(:call).and_return(
          Success({ intent: :out_of_scope, service: nil, input_tokens: 55, output_tokens: 8, model: "test" })
        )
      end

      it "sends a graceful redirect and preserves the step" do
        result = call(body: "¿aceptan tarjeta de crédito?", step: "awaiting_service")

        expect(result).to be_success.and(have_attributes(value!: :answered_question))
        expect(conversation.reload.step).to eq("awaiting_service")
        body_sent = account.message_logs.outbound.order(:created_at).last.body
        expect(body_sent).to include("no la puedo responder directamente")
      end
    end

    context "when QuestionClassifier returns other and ScopeClassifier detects out-of-scope" do
      before do
        allow(Llm::QuestionClassifier).to receive(:call).and_return(Failure(:not_a_question))
        allow(Llm::ScopeClassifier).to receive(:call).and_return(
          Success({ intent: :payment_question, input_tokens: 50, output_tokens: 7, model: "test" })
        )
      end

      it "sends a graceful redirect" do
        result = call(body: "¿aceptan tarjeta o solo efectivo?", step: "awaiting_service")

        expect(result).to be_success.and(have_attributes(value!: :answered_question))
        body_sent = account.message_logs.outbound.order(:created_at).last.body
        expect(body_sent).to include("no la puedo responder directamente")
      end

      it "does not advance the conversation step" do
        call(body: "¿aceptan tarjeta o solo efectivo?", step: "awaiting_service")
        expect(conversation.reload.step).to eq("awaiting_service")
      end
    end

    context "when body is very short (≤ 2 words)" do
      it "does not call ScopeClassifier" do
        allow(Llm::QuestionClassifier).to receive(:call).and_return(Failure(:not_a_question))
        expect(Llm::ScopeClassifier).not_to receive(:call)

        call(body: "ok", step: "awaiting_service")
      end
    end

    context "when ai_nlu_enabled is false" do
      before { account.update!(ai_nlu_enabled: false) }

      it "does not call ScopeClassifier" do
        expect(Llm::ScopeClassifier).not_to receive(:call)

        call(body: "¿aceptan tarjeta o solo efectivo?", step: "awaiting_service")
      end
    end
  end

  # ─── conversation history wiring (Phase 6) ──────────────────────────────────

  describe "conversation history wiring" do
    let(:fake_history) do
      [
        { role: "user",      body: "quiero un corte" },
        { role: "assistant", body: "¿Para cuándo?" }
      ]
    end

    before do
      service
      account.update!(ai_nlu_enabled: true)
      allow(TwilioWebhook::TurnHistory).to receive(:for).and_return(fake_history)
    end

    it "passes turn_history to BookingSlotExtractor" do
      expect(Llm::BookingSlotExtractor).to receive(:call)
        .with(hash_including(history: fake_history))
        .and_return(Failure(:llm_error))

      call(body: "el próximo viernes", step: "awaiting_datetime")
    end

    it "passes turn_history to QuestionClassifier" do
      allow(Llm::QuestionClassifier).to receive(:call).and_return(Failure(:not_a_question))

      expect(Llm::QuestionClassifier).to receive(:call)
        .with(anything, hash_including(history: fake_history))

      call(body: "¿cuánto cuesta el tinte?", step: "awaiting_service")
    end

    it "calls BookingSlotExtractor only once per turn even when multiple methods use it" do
      expect(Llm::BookingSlotExtractor).to receive(:call).once.and_return(Failure(:llm_error))

      call(body: "el próximo viernes", step: "awaiting_datetime")
    end
  end
end
