# frozen_string_literal: true

require "rails_helper"

RSpec.describe ReminderJob, type: :job do
  before do
    allow(GoogleCalendarSyncJob).to receive(:perform_later)
    allow(ReminderJob).to receive(:set).and_return(double(perform_later: true))
  end

  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:service) { create(:service, account: account) }
  let(:customer) { create(:customer, account: account) }
  let(:booking) do
    create(:booking, account: account, user: user, service: service, customer: customer,
           starts_at: 2.days.from_now)
  end

  before do
    # Booking callback already creates the "24h" reminder_schedule
    allow(WhatsappSendJob).to receive(:perform_now)
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

      it "falls back to email without raising an error" do
        expect { described_class.perform_now(booking.id, "24h") }.not_to raise_error
      end

      it "does not send a WhatsApp message" do
        described_class.perform_now(booking.id, "24h")
        expect(WhatsappSendJob).not_to have_received(:perform_now)
      end
    end

    context "when booking does not exist" do
      it "returns without error" do
        expect { described_class.perform_now(0, "24h") }.not_to raise_error
      end
    end
  end
end
