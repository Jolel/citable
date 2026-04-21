# frozen_string_literal: true

require "rails_helper"

RSpec.describe ReminderSchedule, type: :model do
  before do
    allow(GoogleCalendarSyncJob).to receive(:perform_later)
    allow(ReminderJob).to receive(:set).and_return(double(perform_later: true))
  end

  describe "associations" do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:booking) }
  end

  describe "validations" do
    subject { build(:reminder_schedule) }

    it { is_expected.to validate_presence_of(:scheduled_for) }

    it "is invalid with an unknown kind" do
      expect(build(:reminder_schedule, kind: "1h")).not_to be_valid
    end

    it "is valid with kind '24h'" do
      expect(build(:reminder_schedule, kind: "24h")).to be_valid
    end

    it "is valid with kind '2h'" do
      expect(build(:reminder_schedule, kind: "2h")).to be_valid
    end
  end

  describe "scopes" do
    # Each booking auto-creates "24h" and "2h" reminder_schedules via callback.
    # Use separate bookings to avoid the unique (booking_id, kind) constraint.
    let(:account) { create(:account) }

    def make_booking(starts_at: 3.days.from_now)
      create(:booking, account: account,
             user: create(:user, account: account),
             service: create(:service, account: account),
             customer: create(:customer, account: account),
             starts_at: starts_at)
    end

    # booking_a: move its 24h schedule to the past so it is "due"
    let(:booking_a) { make_booking }
    let!(:due_schedule) do
      booking_a.reminder_schedules.find_by(kind: "24h").tap do |s|
        s.update_columns(scheduled_for: 1.hour.ago)
      end
    end

    # booking_b: mark its 24h schedule as sent
    let(:booking_b) { make_booking }
    let!(:sent_schedule) do
      booking_b.reminder_schedules.find_by(kind: "24h").tap do |s|
        s.update_columns(sent_at: 1.hour.ago)
      end
    end

    # booking_c: leave its 24h schedule in the future (pending, not due)
    let(:booking_c) { make_booking }
    let!(:future_schedule) { booking_c.reminder_schedules.find_by(kind: "24h") }

    describe ".pending" do
      it "returns schedules without sent_at" do
        expect(ReminderSchedule.pending).to include(due_schedule, future_schedule)
        expect(ReminderSchedule.pending).not_to include(sent_schedule)
      end
    end

    describe ".sent" do
      it "returns schedules with sent_at" do
        expect(ReminderSchedule.sent).to include(sent_schedule)
        expect(ReminderSchedule.sent).not_to include(due_schedule, future_schedule)
      end
    end

    describe ".due" do
      it "returns pending schedules whose scheduled_for is in the past" do
        expect(ReminderSchedule.due).to include(due_schedule)
        expect(ReminderSchedule.due).not_to include(future_schedule, sent_schedule)
      end
    end
  end

  describe "#sent?" do
    it "returns false when sent_at is nil" do
      expect(build(:reminder_schedule, sent_at: nil).sent?).to be false
    end

    it "returns true when sent_at is set" do
      expect(build(:reminder_schedule, :sent).sent?).to be true
    end
  end

  describe "#mark_sent!" do
    it "sets sent_at to current time" do
      account = create(:account)
      booking = create(:booking, account: account, user: create(:user, account: account),
                       service: create(:service, account: account), customer: create(:customer, account: account))
      schedule = booking.reminder_schedules.find_by(kind: "24h")

      freeze_time do
        schedule.mark_sent!
        expect(schedule.reload.sent_at).to be_within(1.second).of(Time.current)
      end
    end
  end
end
