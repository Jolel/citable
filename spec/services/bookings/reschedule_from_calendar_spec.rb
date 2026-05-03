# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bookings::RescheduleFromCalendar do
  around { |ex| travel_to(Time.zone.local(2026, 4, 13, 9, 0)) { ex.run } }

  before do
    allow(GoogleCalendarSyncJob).to receive(:perform_later)
    allow(ReminderJob).to receive(:set).and_return(double(perform_later: true))
  end

  describe ".call" do
    let(:account) { create(:account) }
    let(:staff) { create(:user, account: account) }
    let(:other_staff) { create(:user, account: account) }
    let(:service) { create(:service, account: account, duration_minutes: 60) }
    let(:customer) { create(:customer, account: account) }
    let(:booking) do
      create(
        :booking,
        account: account,
        user: staff,
        service: service,
        customer: customer,
        starts_at: Time.zone.parse("2026-04-20 10:00"),
        ends_at: Time.zone.parse("2026-04-20 11:00")
      )
    end

    let!(:monday_availability) do
      create(
        :staff_availability,
        account: account,
        user: other_staff,
        day_of_week: 1,
        start_time: "09:00",
        end_time: "18:00"
      )
    end

    it "returns Success with the rescheduled booking" do
      result = described_class.call(
        booking: booking,
        starts_at: Time.zone.parse("2026-04-20 12:00"),
        user: other_staff
      )

      expect(result).to be_success
      expect(result.value![:booking].reload.user).to eq(other_staff)
      expect(result.value![:warnings]).to eq([])
    end

    it "preserves the original duration" do
      described_class.call(
        booking: booking,
        starts_at: Time.zone.parse("2026-04-20 12:30"),
        user: other_staff
      )

      expect(booking.reload.ends_at - booking.starts_at).to eq(60.minutes)
    end

    context "when the new slot overlaps another booking" do
      before do
        create(
          :booking,
          account: account,
          user: other_staff,
          service: service,
          customer: create(:customer, account: account),
          starts_at: Time.zone.parse("2026-04-20 12:30"),
          ends_at: Time.zone.parse("2026-04-20 13:30")
        )
      end

      it "returns overlap as a warning" do
        result = described_class.call(
          booking: booking,
          starts_at: Time.zone.parse("2026-04-20 12:00"),
          user: other_staff
        )

        expect(result).to be_success
        expect(result.value![:warnings]).to include(:overlap)
      end
    end

    context "when the new slot falls outside availability" do
      it "returns outside_availability as a warning" do
        result = described_class.call(
          booking: booking,
          starts_at: Time.zone.parse("2026-04-20 18:30"),
          user: other_staff
        )

        expect(result).to be_success
        expect(result.value![:warnings]).to include(:outside_availability)
      end
    end
  end
end
