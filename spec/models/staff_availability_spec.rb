# frozen_string_literal: true

require "rails_helper"

RSpec.describe StaffAvailability, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:user) }
  end

  describe "validations" do
    subject { build(:staff_availability) }

    it { is_expected.to validate_presence_of(:start_time) }
    it { is_expected.to validate_presence_of(:end_time) }

    it "is invalid when day_of_week is out of 0-6 range" do
      expect(build(:staff_availability, day_of_week: 7)).not_to be_valid
      expect(build(:staff_availability, day_of_week: -1)).not_to be_valid
    end

    it "is valid for each day 0-6" do
      (0..6).each do |day|
        expect(build(:staff_availability, day_of_week: day)).to be_valid
      end
    end

    context "end_time_after_start_time" do
      it "is invalid when end_time equals start_time" do
        avail = build(:staff_availability, start_time: "09:00", end_time: "09:00")
        expect(avail).not_to be_valid
        expect(avail.errors[:end_time]).to be_present
      end

      it "is invalid when end_time is before start_time" do
        avail = build(:staff_availability, start_time: "18:00", end_time: "09:00")
        expect(avail).not_to be_valid
      end

      it "is valid when end_time is after start_time" do
        avail = build(:staff_availability, start_time: "09:00", end_time: "18:00")
        expect(avail).to be_valid
      end
    end
  end

  describe "scopes" do
    let(:account) { create(:account) }
    let(:user) { create(:user, account: account) }
    let!(:active_avail) { create(:staff_availability, account: account, user: user) }
    let!(:inactive_avail) { create(:staff_availability, :inactive, account: account, user: user) }
    let!(:wednesday_avail) { create(:staff_availability, account: account, user: user, day_of_week: 3) }

    describe ".active" do
      it "returns only active availabilities" do
        expect(StaffAvailability.active).to include(active_avail, wednesday_avail)
        expect(StaffAvailability.active).not_to include(inactive_avail)
      end
    end

    describe ".for_day" do
      it "filters by day_of_week" do
        expect(StaffAvailability.for_day(3)).to contain_exactly(wednesday_avail)
      end
    end
  end

  describe "#day_name" do
    it "returns the correct day name" do
      expect(build(:staff_availability, day_of_week: 0).day_name).to eq("sunday")
      expect(build(:staff_availability, day_of_week: 1).day_name).to eq("monday")
      expect(build(:staff_availability, day_of_week: 6).day_name).to eq("saturday")
    end
  end
end
