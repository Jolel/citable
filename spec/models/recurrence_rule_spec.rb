# frozen_string_literal: true

require "rails_helper"

RSpec.describe RecurrenceRule, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to have_many(:bookings).dependent(:nullify) }
  end

  describe "validations" do
    subject { build(:recurrence_rule) }

    it { is_expected.to validate_numericality_of(:interval).is_greater_than(0) }

    it "is invalid with unknown frequency" do
      expect(build(:recurrence_rule, frequency: "daily")).not_to be_valid
    end

    %w[weekly biweekly monthly].each do |freq|
      it "is valid with frequency '#{freq}'" do
        expect(build(:recurrence_rule, frequency: freq)).to be_valid
      end
    end
  end

  describe "#label" do
    it { expect(build(:recurrence_rule, frequency: "weekly").label).to eq("Semanal") }
    it { expect(build(:recurrence_rule, frequency: "biweekly").label).to eq("Quincenal") }
    it { expect(build(:recurrence_rule, frequency: "monthly").label).to eq("Mensual") }
  end

  describe "#next_occurrence_after" do
    let(:base_date) { Date.new(2024, 6, 3) } # a Monday

    it "returns 1 week later for weekly with interval 1" do
      rule = build(:recurrence_rule, frequency: "weekly", interval: 1)
      expect(rule.next_occurrence_after(base_date)).to eq(Date.new(2024, 6, 10))
    end

    it "returns 2 weeks later for weekly with interval 2" do
      rule = build(:recurrence_rule, frequency: "weekly", interval: 2)
      expect(rule.next_occurrence_after(base_date)).to eq(Date.new(2024, 6, 17))
    end

    it "returns 2 weeks later for biweekly with interval 1" do
      rule = build(:recurrence_rule, frequency: "biweekly", interval: 1)
      expect(rule.next_occurrence_after(base_date)).to eq(Date.new(2024, 6, 17))
    end

    it "returns 1 month later for monthly with interval 1" do
      rule = build(:recurrence_rule, frequency: "monthly", interval: 1)
      expect(rule.next_occurrence_after(base_date)).to eq(Date.new(2024, 7, 3))
    end
  end

  describe "#active_on?" do
    it "returns true when no ends_on is set" do
      rule = build(:recurrence_rule, ends_on: nil)
      expect(rule.active_on?(Date.today)).to be true
    end

    it "returns true on or before ends_on" do
      rule = build(:recurrence_rule, ends_on: Date.new(2024, 12, 31))
      expect(rule.active_on?(Date.new(2024, 12, 31))).to be true
      expect(rule.active_on?(Date.new(2024, 6, 1))).to be true
    end

    it "returns false after ends_on" do
      rule = build(:recurrence_rule, ends_on: Date.new(2024, 6, 30))
      expect(rule.active_on?(Date.new(2024, 7, 1))).to be false
    end
  end
end
