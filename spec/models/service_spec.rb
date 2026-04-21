# frozen_string_literal: true

require "rails_helper"

RSpec.describe Service, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to have_many(:bookings).dependent(:restrict_with_error) }
  end

  describe "validations" do
    subject { build(:service) }

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_numericality_of(:duration_minutes).is_greater_than(0) }
    it { is_expected.to validate_numericality_of(:price_cents).is_greater_than_or_equal_to(0) }
    it { is_expected.to validate_numericality_of(:deposit_amount_cents).is_greater_than_or_equal_to(0) }
  end

  describe "scopes" do
    let(:account) { create(:account) }
    let!(:active_service) { create(:service, account: account) }
    let!(:inactive_service) { create(:service, :inactive, account: account) }

    describe ".active" do
      it "returns only active services" do
        expect(account.services.active).to contain_exactly(active_service)
      end
    end
  end

  describe "#deposit_required?" do
    it "returns false when deposit is zero" do
      expect(build(:service, deposit_amount_cents: 0).deposit_required?).to be false
    end

    it "returns true when deposit is greater than zero" do
      expect(build(:service, :with_deposit).deposit_required?).to be true
    end
  end

  describe "#duration_label" do
    it "formats 60 minutes as '1h'" do
      expect(build(:service, duration_minutes: 60).duration_label).to eq("1h")
    end

    it "formats 90 minutes as '1h 30min'" do
      expect(build(:service, duration_minutes: 90).duration_label).to eq("1h 30min")
    end

    it "formats 45 minutes as '45min'" do
      expect(build(:service, duration_minutes: 45).duration_label).to eq("45min")
    end

    it "formats 120 minutes as '2h'" do
      expect(build(:service, duration_minutes: 120).duration_label).to eq("2h")
    end
  end

  describe "money columns" do
    it "exposes price as Money object" do
      service = build(:service, price_cents: 50000)
      expect(service.price).to eq(Money.new(50000, "MXN"))
    end

    it "exposes deposit_amount as Money object" do
      service = build(:service, deposit_amount_cents: 10000)
      expect(service.deposit_amount).to eq(Money.new(10000, "MXN"))
    end
  end
end
