# frozen_string_literal: true

require "rails_helper"

RSpec.describe TwilioWebhook::CorrectionDetector do
  include Dry::Monads[:result]

  let(:account)      { create(:account) }
  let(:service)      { create(:service, account: account, name: "Corte de cabello", requires_address: false) }
  let(:service_b)    { create(:service, account: account, name: "Tinte", requires_address: false) }
  let(:customer)     { create(:customer, account: account) }
  let(:llm)          { instance_double(Llm::Port) }
  let(:locked_time)  { Time.zone.parse("2026-05-09T15:00:00") }

  def conversation_at(step:, service: nil, starts_at: nil)
    create(:whatsapp_conversation,
           account:              account,
           customer:             customer,
           step:                 step,
           service:              service,
           requested_starts_at:  starts_at)
  end

  def stub_extractor(slots:)
    allow(Llm::BookingSlotExtractor).to receive(:call).and_return(
      Success({
        slots:          slots,
        confidences:    { service: 0.9, datetime: 0.88, address: 0.0, confirmation: 0.0 },
        top_candidates: [],
        input_tokens:   90,
        output_tokens:  16,
        model:          "test"
      })
    )
  end

  describe ".call" do
    context "when no slots are locked yet" do
      it "returns Failure(:no_locked_slots)" do
        conv = conversation_at(step: "awaiting_service")
        result = described_class.call(body: "espera, mejor el tinte", conversation: conv, account: account)
        expect(result).to be_failure.and(have_attributes(failure: :no_locked_slots))
      end
    end

    context "when the extractor returns Failure" do
      it "returns Failure(:llm_error)" do
        conv = conversation_at(step: "confirming_booking", service: service, starts_at: locked_time)
        allow(Llm::BookingSlotExtractor).to receive(:call).and_return(Failure(:llm_error))

        result = described_class.call(body: "espera, mejor el sábado", conversation: conv, account: account)
        expect(result).to be_failure.and(have_attributes(failure: :llm_error))
      end
    end

    context "when the extractor returns slots that did not change anything" do
      it "returns Failure(:nothing_changed)" do
        conv = conversation_at(step: "confirming_booking", service: service, starts_at: locked_time)
        stub_extractor(slots: { service: nil, starts_at: nil, address: nil, confirmation: nil })

        result = described_class.call(body: "espera, el mismo servicio", conversation: conv, account: account)
        expect(result).to be_failure.and(have_attributes(failure: :nothing_changed))
      end
    end

    context "when only starts_at changes" do
      let(:new_time) { Time.zone.parse("2026-05-10T17:00:00") }

      before do
        stub_extractor(slots: { service: nil, starts_at: new_time, address: nil, confirmation: nil })
      end

      it "returns Success with rewound_to: confirming_booking" do
        conv = conversation_at(step: "confirming_booking", service: service, starts_at: locked_time)
        result = described_class.call(body: "mejor el sábado a las 5", conversation: conv, account: account)

        expect(result).to be_success
        expect(result.value![:rewound_to]).to eq("confirming_booking")
        expect(result.value![:applied_slots]).to eq([ :starts_at ])
      end

      it "updates the conversation's requested_starts_at" do
        conv = conversation_at(step: "confirming_booking", service: service, starts_at: locked_time)
        described_class.call(body: "mejor el sábado a las 5", conversation: conv, account: account)

        expect(conv.reload.requested_starts_at).to be_within(1.second).of(new_time)
      end

      it "sets conversation.step to confirming_booking" do
        conv = conversation_at(step: "confirming_booking", service: service, starts_at: locked_time)
        described_class.call(body: "mejor el sábado a las 5", conversation: conv, account: account)

        expect(conv.reload.step).to eq("confirming_booking")
      end
    end

    context "when service changes and no datetime is locked" do
      before do
        stub_extractor(slots: { service: service_b, starts_at: nil, address: nil, confirmation: nil })
      end

      it "rewinds to awaiting_datetime" do
        conv = conversation_at(step: "confirming_booking", service: service)
        result = described_class.call(body: "espera, mejor el tinte", conversation: conv, account: account)

        expect(result).to be_success
        expect(result.value![:rewound_to]).to eq("awaiting_datetime")
        expect(conv.reload.service).to eq(service_b)
      end
    end

    context "when service changes and datetime is already set" do
      before do
        stub_extractor(slots: { service: service_b, starts_at: nil, address: nil, confirmation: nil })
      end

      it "rewinds to confirming_booking (datetime already known)" do
        conv = conversation_at(step: "confirming_booking", service: service, starts_at: locked_time)
        result = described_class.call(body: "espera, mejor el tinte", conversation: conv, account: account)

        expect(result).to be_success
        expect(result.value![:rewound_to]).to eq("confirming_booking")
      end
    end

    it "includes token usage in the Success hash" do
      conv = conversation_at(step: "confirming_booking", service: service, starts_at: locked_time)
      new_time = locked_time + 2.hours
      stub_extractor(slots: { service: nil, starts_at: new_time, address: nil, confirmation: nil })

      result = described_class.call(body: "mejor un poco más tarde", conversation: conv, account: account)

      expect(result.value![:input_tokens]).to eq(90)
      expect(result.value![:output_tokens]).to eq(16)
      expect(result.value![:model]).to eq("test")
    end
  end
end
