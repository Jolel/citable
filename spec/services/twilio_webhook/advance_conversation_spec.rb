# frozen_string_literal: true

require "rails_helper"

RSpec.describe TwilioWebhook::AdvanceConversation do
  # Suppress outbound Twilio sends and calendar syncs throughout.
  before do
    allow_any_instance_of(Whatsapp::MessageSender).to receive(:deliver).and_return(nil)
    allow(GoogleCalendarSyncJob).to receive(:perform_later)
    allow(ReminderJob).to receive(:set).and_return(double(perform_later: true))
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

      let(:nlu_result) do
        Llm::NluParser::Result.new(value: service, input_tokens: 80, output_tokens: 15, model: "gemini-2.0-flash")
      end

      it "calls the NLU parser and advances to awaiting_datetime" do
        allow(Llm::NluParser).to receive(:parse_service).and_return(nlu_result)

        result = call(body: "quiero un corte", step: "awaiting_service")

        expect(result).to be_success
        expect(conversation.reload.step).to eq("awaiting_datetime")
        expect(conversation.reload.service).to eq(service)
      end

      it "records AI token usage on the most recent inbound MessageLog" do
        create(:message_log, account: account, customer: customer,
               channel: "whatsapp", direction: "inbound", body: "quiero un corte", status: "delivered")

        allow(Llm::NluParser).to receive(:parse_service).and_return(nlu_result)
        call(body: "quiero un corte", step: "awaiting_service")

        log = account.message_logs.inbound.order(:created_at).last
        expect(log.ai_input_tokens).to eq(80)
        expect(log.ai_output_tokens).to eq(15)
        expect(log.ai_model).to eq("gemini-2.0-flash")
      end

      context "when the NLU parser returns nil (low confidence / error)" do
        it "re-prompts without advancing" do
          allow(Llm::NluParser).to receive(:parse_service).and_return(nil)

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
      let(:nlu_result) do
        Llm::NluParser::Result.new(value: parsed_time, input_tokens: 95, output_tokens: 18, model: "gemini-2.0-flash")
      end

      it "calls the NLU parser and advances to confirming_booking" do
        allow(Llm::NluParser).to receive(:parse_datetime).and_return(nlu_result)

        result = call(body: "viernes a las 3", step: "awaiting_datetime")

        expect(result).to be_success
        expect(conversation.reload.step).to eq("confirming_booking")
        expect(conversation.reload.requested_starts_at).to be_within(1.second).of(parsed_time)
      end

      context "when the NLU parser returns nil" do
        it "re-prompts without advancing" do
          allow(Llm::NluParser).to receive(:parse_datetime).and_return(nil)

          result = call(body: "no sé cuándo", step: "awaiting_datetime")

          expect(result).to be_success.and(have_attributes(value!: :awaiting_datetime))
          expect(conversation.reload.step).to eq("awaiting_datetime")
        end
      end
    end
  end
end
