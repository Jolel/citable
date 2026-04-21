# frozen_string_literal: true

require "rails_helper"

RSpec.describe Booking, type: :model do
  # Suppress job enqueueing for all tests in this file
  before do
    allow(GoogleCalendarSyncJob).to receive(:perform_later)
    allow(ReminderJob).to receive(:set).and_return(double(perform_later: true))
  end

  describe "associations" do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:customer) }
    it { is_expected.to belong_to(:service) }
    it { is_expected.to belong_to(:user) }
    it { is_expected.to belong_to(:recurrence_rule).optional }
    it { is_expected.to have_many(:message_logs).dependent(:destroy) }
    it { is_expected.to have_many(:reminder_schedules).dependent(:destroy) }
  end

  describe "validations" do
    subject { build(:booking) }

    it { is_expected.to validate_presence_of(:starts_at) }
    # ends_at is auto-set by set_ends_at callback so presence is always satisfied
    it { is_expected.to validate_presence_of(:status) }
    it { is_expected.to validate_presence_of(:deposit_state) }

    context "ends_at_after_starts_at" do
      it "is invalid when ends_at is before starts_at" do
        booking = build(:booking,
          starts_at: 2.hours.from_now,
          ends_at: 1.hour.from_now
        )
        expect(booking).not_to be_valid
        expect(booking.errors[:ends_at]).to be_present
      end

      it "is invalid when ends_at equals starts_at" do
        time = 2.hours.from_now
        booking = build(:booking, starts_at: time, ends_at: time)
        expect(booking).not_to be_valid
      end
    end

    context "address_required_for_service" do
      let(:service) { create(:service, :requires_address) }

      it "is invalid when service requires address but none given" do
        booking = build(:booking, service: service, address: nil)
        expect(booking).not_to be_valid
        expect(booking.errors[:address]).to be_present
      end

      it "is valid when service requires address and it is given" do
        booking = build(:booking, service: service, address: "Calle 5 #10, Col. Centro")
        expect(booking).to be_valid
      end
    end
  end

  describe "enums" do
    it "has the expected status values" do
      expect(Booking.statuses).to eq(
        "pending" => "pending", "confirmed" => "confirmed",
        "cancelled" => "cancelled", "no_show" => "no_show", "completed" => "completed"
      )
    end
  end

  describe "scopes" do
    let(:account) { create(:account) }
    let(:user) { create(:user, account: account) }
    let(:service) { create(:service, account: account) }
    let(:customer) { create(:customer, account: account) }

    let!(:upcoming_booking) do
      create(:booking, account: account, user: user, service: service, customer: customer,
             starts_at: 2.days.from_now)
    end
    let!(:past_booking) do
      create(:booking, :past, account: account, user: user, service: service, customer: customer)
    end
    let!(:active_booking) do
      create(:booking, :confirmed, account: account, user: user, service: service, customer: customer,
             starts_at: 3.days.from_now)
    end
    let!(:cancelled_booking) do
      create(:booking, :cancelled, account: account, user: user, service: service, customer: customer,
             starts_at: 1.day.from_now)
    end

    describe ".upcoming" do
      it "returns bookings with starts_at in the future" do
        results = account.bookings.upcoming
        expect(results).to include(upcoming_booking, active_booking, cancelled_booking)
        expect(results).not_to include(past_booking)
      end
    end

    describe ".past" do
      it "returns bookings with starts_at in the past" do
        expect(account.bookings.past).to include(past_booking)
        expect(account.bookings.past).not_to include(upcoming_booking)
      end
    end

    describe ".active" do
      it "returns pending and confirmed bookings" do
        expect(account.bookings.active).to include(upcoming_booking, active_booking)
        expect(account.bookings.active).not_to include(cancelled_booking)
      end
    end
  end

  describe "#set_ends_at" do
    it "sets ends_at based on service duration when not provided" do
      service = build(:service, duration_minutes: 90)
      starts = 1.day.from_now
      booking = build(:booking, service: service, starts_at: starts, ends_at: nil)
      booking.valid?
      expect(booking.ends_at).to be_within(1.second).of(starts + 90.minutes)
    end

    it "does not override an explicitly set ends_at" do
      explicit_end = 2.days.from_now
      booking = build(:booking, ends_at: explicit_end)
      booking.valid?
      expect(booking.ends_at).to be_within(1.second).of(explicit_end)
    end
  end

  describe "#confirm!" do
    it "sets status to confirmed and records confirmed_at" do
      booking = create(:booking)
      expect { booking.confirm! }.to change { booking.status }.to("confirmed")
      expect(booking.confirmed_at).to be_present
    end
  end

  describe "#cancel!" do
    it "sets status to cancelled" do
      booking = create(:booking)
      booking.cancel!
      expect(booking).to be_cancelled
    end

    it "enqueues a cancel GoogleCalendarSyncJob" do
      booking = create(:booking)
      booking.cancel!
      expect(GoogleCalendarSyncJob).to have_received(:perform_later).with(booking.id, "cancel")
    end
  end

  describe "#recurring?" do
    it "returns false when no recurrence rule" do
      booking = build(:booking, recurrence_rule: nil)
      expect(booking.recurring?).to be false
    end

    it "returns true when recurrence_rule_id is set" do
      booking = build(:booking)
      booking.recurrence_rule_id = 999
      expect(booking.recurring?).to be true
    end
  end

  describe "#deposit_required?" do
    it "returns false when service has no deposit" do
      booking = build(:booking, service: build(:service, deposit_amount_cents: 0))
      expect(booking.deposit_required?).to be false
    end

    it "returns true when service requires a deposit" do
      booking = build(:booking, service: build(:service, :with_deposit))
      expect(booking.deposit_required?).to be true
    end
  end

  describe "after_create_commit callbacks" do
    it "enqueues GoogleCalendarSyncJob on create" do
      account = create(:account)
      create(:booking,
        account: account,
        user: create(:user, account: account),
        service: create(:service, account: account),
        customer: create(:customer, account: account)
      )
      expect(GoogleCalendarSyncJob).to have_received(:perform_later).with(anything, "create")
    end
  end
end
