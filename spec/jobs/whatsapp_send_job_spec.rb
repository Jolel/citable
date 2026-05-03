# frozen_string_literal: true

require "rails_helper"

RSpec.describe WhatsappSendJob, type: :job do
  # Freeze before the hard-coded 2026 booking date so starts_at_in_future
  # accepts the fixture and the per-job behavior under test is reproducible.
  around { |ex| travel_to(Time.zone.local(2026, 4, 13, 9, 0)) { ex.run } }

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
      starts_at: Time.zone.parse("2026-04-20 10:00:00")
    )
  end

  let(:twilio_message_double) { double(sid: "SM123abc") }
  let(:twilio_messages_double) { double("twilio_messages", create: twilio_message_double) }
  let(:twilio_client_double) { double("twilio_client", messages: twilio_messages_double) }

  before do
    allow(Rails.application.credentials).to receive(:dig).with(:twilio, :account_sid).and_return("AC_TEST")
    allow(Rails.application.credentials).to receive(:dig).with(:twilio, :auth_token).and_return("AUTH_TEST")
    allow(Rails.application.credentials).to receive(:dig).with(:twilio, :whatsapp_number).and_return("14155238886")
    allow(Twilio::REST::Client).to receive(:new).and_return(twilio_client_double)
    allow(twilio_messages_double).to receive(:create).and_return(twilio_message_double)
  end

  describe "#perform" do
    context "when quota is not exceeded" do
      it "sends a WhatsApp message via Twilio" do
        described_class.perform_now(booking.id, :confirmation)
        expect(twilio_messages_double).to have_received(:create).with(
          hash_including(to: "whatsapp:+5215512345678")
        )
      end

      it "creates a MessageLog record" do
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

      it "does not call Twilio" do
        described_class.perform_now(booking.id, :confirmation)
        expect(twilio_messages_double).not_to have_received(:create)
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

    context "when Twilio raises an error" do
      before do
        allow(twilio_messages_double).to receive(:create)
          .and_raise(Twilio::REST::TwilioError.new("Network error"))
      end

      it "creates a failed MessageLog" do
        expect {
          described_class.perform_now(booking.id, :confirmation) rescue nil
        }.to change(MessageLog, :count).by(1)

        expect(MessageLog.last.status).to eq("failed")
      end

      it "re-raises as a generic error for Solid Queue retry" do
        expect {
          described_class.perform_now(booking.id, :confirmation)
        }.to raise_error(RuntimeError, /WhatsApp delivery failed/)
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
