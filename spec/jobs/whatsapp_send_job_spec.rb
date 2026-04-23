# frozen_string_literal: true

require "rails_helper"
require "infrastructure/adapters/twilio_adapter"
require "core/use_cases/send_whatsapp_message"

RSpec.describe WhatsappSendJob, type: :job do
  include Dry::Monads[:result]

  before do
    allow(GoogleCalendarSyncJob).to receive(:perform_later)
    allow(ReminderJob).to receive(:set).and_return(double(perform_later: true))
  end

  let(:account) { create(:account, name: "Estudio Ana") }
  let(:customer) { create(:customer, account: account, name: "María", phone: "+5215512345678") }
  let(:user) { create(:user, account: account) }
  let(:service) { create(:service, account: account, duration_minutes: 60) }
  let(:booking) do
    create(:booking,
      account: account,
      customer: customer,
      user: user,
      service: service,
      starts_at: Time.zone.parse("2024-08-15 10:00:00")
    )
  end

  let(:sent_message) do
    Infrastructure::Adapters::TwilioAdapter::SentMessage.new(sid: "SM123abc", status: "queued")
  end
  let(:use_case_double) { instance_double(Core::UseCases::SendWhatsappMessage) }

  before do
    # Stub the container lookup so the job receives our double without a real Twilio client.
    allow(Citable::Container).to receive(:[])
      .with("core.use_cases.send_whatsapp_message")
      .and_return(use_case_double)
    allow(use_case_double).to receive(:call).and_return(Success(sent_message))
  end

  describe "#perform" do
    context "when quota is not exceeded" do
      it "calls the use case with the customer phone and message body" do
        described_class.perform_now(booking.id, :confirmation)
        expect(use_case_double).to have_received(:call).with(
          hash_including(to: "+5215512345678")
        )
      end

      it "creates a sent MessageLog record" do
        expect {
          described_class.perform_now(booking.id, :confirmation)
        }.to change(MessageLog, :count).by(1)

        log = MessageLog.last
        expect(log.channel).to eq("whatsapp")
        expect(log.direction).to eq("outbound")
        expect(log.status).to eq("sent")
        expect(log.external_id).to eq("SM123abc")
      end

      it "increments the account's whatsapp_quota_used" do
        expect {
          described_class.perform_now(booking.id, :confirmation)
        }.to change { account.reload.whatsapp_quota_used }.by(1)
      end
    end

    context "when quota is exceeded" do
      before { account.update!(whatsapp_quota_used: 100) }

      it "does not call the use case" do
        described_class.perform_now(booking.id, :confirmation)
        expect(use_case_double).not_to have_received(:call)
      end

      it "does not create a MessageLog" do
        expect {
          described_class.perform_now(booking.id, :confirmation)
        }.not_to change(MessageLog, :count)
      end
    end

    context "when booking does not exist" do
      it "returns without error" do
        expect { described_class.perform_now(0, :confirmation) }.not_to raise_error
      end
    end

    context "when the use case returns Failure (Twilio error)" do
      let(:twilio_error) { Core::Errors::ExternalServiceError.new("Network error") }

      before do
        allow(use_case_double).to receive(:call).and_return(Failure(twilio_error))
      end

      it "creates a failed MessageLog" do
        expect {
          described_class.perform_now(booking.id, :confirmation) rescue nil
        }.to change(MessageLog, :count).by(1)

        expect(MessageLog.last.status).to eq("failed")
      end

      it "re-raises the error as ExternalServiceError" do
        expect {
          described_class.perform_now(booking.id, :confirmation)
        }.to raise_error(Core::Errors::ExternalServiceError)
      end
    end

    context "message content" do
      it "builds a confirmation message mentioning customer and account name" do
        described_class.perform_now(booking.id, :confirmation)
        body = MessageLog.last.body
        expect(body).to include("María")
        expect(body).to include("Estudio Ana")
      end

      it "builds a 24h reminder message asking for confirmation" do
        described_class.perform_now(booking.id, :"24h")
        body = MessageLog.last.body
        expect(body).to include("mañana")
        expect(body).to include("1")
        expect(body).to include("2")
      end

      it "builds a 2h reminder message" do
        described_class.perform_now(booking.id, :"2h")
        body = MessageLog.last.body
        expect(body).to include("2 horas")
      end
    end
  end
end
