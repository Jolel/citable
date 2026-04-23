# frozen_string_literal: true

require "rails_helper"
require "infrastructure/adapters/twilio_adapter"
require "core/use_cases/send_whatsapp_message"

RSpec.describe Core::UseCases::SendWhatsappMessage do
  # Inject the adapter double directly — dry-auto_inject accepts keyword overrides
  # in the constructor, so no container stubbing or allow_any_instance_of needed.
  subject(:use_case) { described_class.new(twilio_adapter: adapter) }

  let(:adapter) { instance_double(Infrastructure::Adapters::TwilioAdapter) }
  let(:sent_message) do
    Infrastructure::Adapters::TwilioAdapter::SentMessage.new(sid: "SM123abc", status: "queued")
  end

  describe "#call" do
    context "when the adapter sends successfully" do
      before do
        allow(adapter).to receive(:send_message)
          .with(to: "+5215512345678", from: "+12345678901", body: "Hola!")
          .and_return(sent_message)
      end

      it "returns Success" do
        result = use_case.call(to: "+5215512345678", from: "+12345678901", body: "Hola!")
        expect(result).to be_success
      end

      it "wraps the SentMessage in the result" do
        result = use_case.call(to: "+5215512345678", from: "+12345678901", body: "Hola!")
        expect(result.value!.sid).to eq("SM123abc")
        expect(result.value!.status).to eq("queued")
      end
    end

    context "when the adapter raises ExternalServiceError" do
      before do
        allow(adapter).to receive(:send_message)
          .and_raise(Core::Errors::ExternalServiceError, "21211: invalid 'To' phone number")
      end

      it "returns Failure" do
        result = use_case.call(to: "bad-number", from: "+1", body: "x")
        expect(result).to be_failure
      end

      it "wraps the error in the failure value" do
        result = use_case.call(to: "bad-number", from: "+1", body: "x")
        expect(result.failure).to be_a(Core::Errors::ExternalServiceError)
        expect(result.failure.message).to include("21211")
      end
    end
  end
end
