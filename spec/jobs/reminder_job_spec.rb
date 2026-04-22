# frozen_string_literal: true

require "rails_helper"

RSpec.describe ReminderJob, type: :job do
  before do
    allow(GoogleCalendarSyncJob).to receive(:perform_later)
    allow(ReminderJob).to receive(:set).and_return(double(perform_later: true))
    allow(WhatsappSendJob).to receive(:perform_now)
    allow(Resend::Emails).to receive(:send).and_return({ id: "resend-abc-123" })
  end

  let(:account) { create(:account) }
  let(:owner) { create(:user, account: account, role: "owner", email: "owner@example.com") }
  let(:service) { create(:service, account: account) }
  let(:customer) { create(:customer, account: account) }
  let(:booking) do
    create(:booking, account: account, user: owner, service: service, customer: customer,
           starts_at: 2.days.from_now)
  end

  describe "#perform" do
    context "when booking exists and is not cancelled" do
      it "sends a whatsapp reminder when quota is available" do
        described_class.perform_now(booking.id, "24h")
        expect(WhatsappSendJob).to have_received(:perform_now).with(booking.id, :"24h")
      end

      it "marks the reminder schedule as sent" do
        schedule = booking.reminder_schedules.find_by(kind: "24h")
        expect { described_class.perform_now(booking.id, "24h") }
          .to change { schedule.reload.sent_at }.from(nil)
      end
    end

    context "when booking is cancelled" do
      before { booking.update_columns(status: "cancelled") }

      it "does not send any reminder" do
        described_class.perform_now(booking.id, "24h")
        expect(WhatsappSendJob).not_to have_received(:perform_now)
        expect(Resend::Emails).not_to have_received(:send)
      end
    end

    context "when reminder was already sent" do
      before { booking.reminder_schedules.find_by(kind: "24h").mark_sent! }

      it "does not send again" do
        described_class.perform_now(booking.id, "24h")
        expect(WhatsappSendJob).not_to have_received(:perform_now)
      end
    end

    context "when whatsapp quota is exceeded" do
      before { account.update!(whatsapp_quota_used: 100) }

      it "does not send a WhatsApp message" do
        described_class.perform_now(booking.id, "24h")
        expect(WhatsappSendJob).not_to have_received(:perform_now)
      end

      it "sends a fallback email to the owner" do
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

      it "marks the reminder schedule as sent" do
        schedule = booking.reminder_schedules.find_by(kind: "24h")
        expect { described_class.perform_now(booking.id, "24h") }
          .to change { schedule.reload.sent_at }.from(nil)
      end

      context "when account has no owner" do
        before { owner.update!(role: "staff") }

        it "does not call Resend" do
          described_class.perform_now(booking.id, "24h")
          expect(Resend::Emails).not_to have_received(:send)
        end

        it "does not raise an error" do
          expect { described_class.perform_now(booking.id, "24h") }.not_to raise_error
        end
      end
    end

    context "when booking does not exist" do
      it "returns without error" do
        expect { described_class.perform_now(0, "24h") }.not_to raise_error
      end
    end
  end
end
