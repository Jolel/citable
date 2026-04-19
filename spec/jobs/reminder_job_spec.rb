require "rails_helper"

RSpec.describe ReminderJob, type: :job do
  let(:account)  { create(:account, plan: "free", whatsapp_quota_used: 0) }
  let(:owner)    { create(:user, account: account, role: "owner", email: "duena@example.com") }
  let(:customer) { create(:customer, account: account) }
  let(:service)  { create(:service, account: account) }
  let(:booking)  { create(:booking, account: account, customer: customer, service: service, user: owner) }
  let!(:schedule) do
    create(:reminder_schedule, account: account, booking: booking,
           kind: "24h", scheduled_for: 1.hour.ago)
  end

  before do
    ActsAsTenant.test_tenant = account
    allow(WhatsappSendJob).to receive(:perform_now)
    allow(Resend::Emails).to receive(:send).and_return({ id: "resend-abc-123" })
  end
  after { ActsAsTenant.test_tenant = nil }

  describe "#perform" do
    context "when booking does not exist" do
      it "returns without error" do
        expect { described_class.perform_now(0, "24h") }.not_to raise_error
      end
    end

    context "when booking is cancelled" do
      before { booking.update!(status: "cancelled") }

      it "does not send any message" do
        described_class.perform_now(booking.id, "24h")
        expect(WhatsappSendJob).not_to have_received(:perform_now)
        expect(Resend::Emails).not_to have_received(:send)
      end
    end

    context "when quota is not exceeded" do
      it "delegates to WhatsappSendJob with symbolized kind" do
        described_class.perform_now(booking.id, "24h")
        expect(WhatsappSendJob).to have_received(:perform_now).with(booking.id, :"24h")
      end

      it "marks the schedule as sent" do
        described_class.perform_now(booking.id, "24h")
        expect(schedule.reload.sent?).to be true
      end

      it "does not call Resend" do
        described_class.perform_now(booking.id, "24h")
        expect(Resend::Emails).not_to have_received(:send)
      end
    end

    context "when quota is exceeded" do
      before { account.update!(whatsapp_quota_used: 100) }

      it "does not call WhatsappSendJob" do
        described_class.perform_now(booking.id, "24h")
        expect(WhatsappSendJob).not_to have_received(:perform_now)
      end

      it "sends an email to the owner" do
        described_class.perform_now(booking.id, "24h")
        expect(Resend::Emails).to have_received(:send).with(
          hash_including(to: owner.email)
        )
      end

      it "creates an email outbound MessageLog with status sent" do
        expect { described_class.perform_now(booking.id, "24h") }
          .to change(MessageLog, :count).by(1)
        log = MessageLog.last
        expect(log.channel).to eq("email")
        expect(log.direction).to eq("outbound")
        expect(log.status).to eq("sent")
      end

      it "marks the schedule as sent" do
        described_class.perform_now(booking.id, "24h")
        expect(schedule.reload.sent?).to be true
      end

      context "when account has no owner" do
        before { owner.update!(role: "staff") }

        it "does not call Resend" do
          described_class.perform_now(booking.id, "24h")
          expect(Resend::Emails).not_to have_received(:send)
        end
      end
    end

    context "when schedule is already sent (idempotency)" do
      before { schedule.mark_sent! }

      it "does not send any message" do
        described_class.perform_now(booking.id, "24h")
        expect(WhatsappSendJob).not_to have_received(:perform_now)
        expect(Resend::Emails).not_to have_received(:send)
      end
    end

    context "when no ReminderSchedule exists for this kind" do
      before { schedule.destroy }

      it "still sends via WhatsApp" do
        described_class.perform_now(booking.id, "24h")
        expect(WhatsappSendJob).to have_received(:perform_now)
      end
    end
  end
end
