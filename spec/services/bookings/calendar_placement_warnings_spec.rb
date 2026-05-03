# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bookings::CalendarPlacementWarnings do
  # Hardcoded fixture dates land on Monday 2026-04-20; freeze "now" before
  # that so the booking model's starts_at_in_future validation accepts them.
  around { |ex| travel_to(Time.zone.local(2026, 4, 13, 9, 0)) { ex.run } }

  before do
    allow(GoogleCalendarSyncJob).to receive(:perform_later)
    allow(ReminderJob).to receive(:set).and_return(double(perform_later: true))
  end

  describe ".call" do
    let(:account) { create(:account) }
    let(:user) { create(:user, account: account) }
    let(:service) { create(:service, account: account, duration_minutes: 60) }
    let(:customer) { create(:customer, account: account) }
    let(:booking) do
      create(
        :booking,
        account: account,
        user: user,
        service: service,
        customer: customer,
        starts_at: Time.zone.parse("2026-04-20 10:00"),
        ends_at: Time.zone.parse("2026-04-20 11:00")
      )
    end

    context "when the user has no availability record for that day" do
      it "returns outside_availability warning" do
        result = described_class.call(
          booking: booking,
          starts_at: booking.starts_at,
          ends_at: booking.ends_at,
          user: user
        )

        expect(result).to be_success
        expect(result.value!).to include(:outside_availability)
      end
    end

    context "when the booking falls within availability" do
      before do
        create(
          :staff_availability,
          account: account,
          user: user,
          day_of_week: 1,
          start_time: "09:00",
          end_time: "18:00"
        )
      end

      it "returns no warnings" do
        result = described_class.call(
          booking: booking,
          starts_at: booking.starts_at,
          ends_at: booking.ends_at,
          user: user
        )

        expect(result).to be_success
        expect(result.value!).to eq([])
      end
    end

    context "when the booking falls outside availability hours" do
      before do
        create(
          :staff_availability,
          account: account,
          user: user,
          day_of_week: 1,
          start_time: "09:00",
          end_time: "10:30"
        )
      end

      it "returns outside_availability warning" do
        result = described_class.call(
          booking: booking,
          starts_at: booking.starts_at,
          ends_at: booking.ends_at,
          user: user
        )

        expect(result).to be_success
        expect(result.value!).to include(:outside_availability)
      end
    end

    context "when the slot overlaps another active booking" do
      before do
        create(
          :staff_availability,
          account: account,
          user: user,
          day_of_week: 1,
          start_time: "09:00",
          end_time: "18:00"
        )
        create(
          :booking,
          account: account,
          user: user,
          service: service,
          customer: create(:customer, account: account),
          starts_at: Time.zone.parse("2026-04-20 10:30"),
          ends_at: Time.zone.parse("2026-04-20 11:30")
        )
      end

      it "returns overlap warning" do
        result = described_class.call(
          booking: booking,
          starts_at: booking.starts_at,
          ends_at: booking.ends_at,
          user: user
        )

        expect(result).to be_success
        expect(result.value!).to include(:overlap)
      end
    end
  end
end
