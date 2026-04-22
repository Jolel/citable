# frozen_string_literal: true

require "rails_helper"

RSpec.describe Account, type: :model do
  describe "associations" do
    it { is_expected.to have_many(:users).dependent(:destroy) }
    it { is_expected.to have_many(:services).dependent(:destroy) }
    it { is_expected.to have_many(:customers).dependent(:destroy) }
    it { is_expected.to have_many(:bookings).dependent(:destroy) }
    it { is_expected.to have_many(:recurrence_rules).dependent(:destroy) }
    it { is_expected.to have_many(:message_logs).dependent(:destroy) }
    it { is_expected.to have_many(:reminder_schedules).dependent(:destroy) }
  end

  describe "validations" do
    subject { build(:account) }

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:subdomain) }
    it { is_expected.to validate_uniqueness_of(:subdomain).case_insensitive }
    it { is_expected.to validate_presence_of(:timezone) }
    it { is_expected.to validate_presence_of(:locale) }
    it { is_expected.to validate_numericality_of(:whatsapp_quota_used).is_greater_than_or_equal_to(0) }

    it "is invalid with an uppercase subdomain" do
      account = build(:account, subdomain: "MyShop")
      account.valid?
      expect(account.subdomain).to eq("myshop")
    end

    it "is invalid with subdomain containing special characters" do
      account = build(:account, subdomain: "my shop!")
      expect(account).not_to be_valid
      expect(account.errors[:subdomain]).to be_present
    end

    it "accepts subdomain with hyphens and numbers" do
      account = build(:account, subdomain: "ana-studio-2")
      expect(account).to be_valid
    end

    it "validates plan is in allowed values" do
      account = build(:account, plan: "enterprise")
      expect(account).not_to be_valid
    end
  end

  describe "#downcase_subdomain" do
    it "downcases subdomain before validation" do
      account = build(:account, subdomain: "AnaStudio")
      account.valid?
      expect(account.subdomain).to eq("anastudio")
    end

    it "strips whitespace from subdomain" do
      account = build(:account, subdomain: "  ana  ")
      account.valid?
      expect(account.subdomain).to eq("ana")
    end
  end

  describe "#whatsapp_quota_limit" do
    it "returns 100 for free plan" do
      account = build(:account, plan: "free")
      expect(account.whatsapp_quota_limit).to eq(100)
    end

    it "returns 1000 for pro plan" do
      account = build(:account, plan: "pro")
      expect(account.whatsapp_quota_limit).to eq(1000)
    end

    it "defaults to 100 for unknown plan" do
      account = build(:account)
      allow(account).to receive(:plan).and_return("unknown")
      expect(account.whatsapp_quota_limit).to eq(100)
    end
  end

  describe "#whatsapp_quota_exceeded?" do
    it "returns false when under quota" do
      account = build(:account, plan: "free", whatsapp_quota_used: 50)
      expect(account.whatsapp_quota_exceeded?).to be false
    end

    it "returns true when at quota limit" do
      account = build(:account, :quota_exceeded)
      expect(account.whatsapp_quota_exceeded?).to be true
    end

    it "returns true when over quota" do
      account = build(:account, plan: "free", whatsapp_quota_used: 150)
      expect(account.whatsapp_quota_exceeded?).to be true
    end

    it "uses pro quota for pro plan" do
      account = build(:account, plan: "pro", whatsapp_quota_used: 500)
      expect(account.whatsapp_quota_exceeded?).to be false
    end
  end

  describe "#free? / #pro?" do
    it "returns true for free plan" do
      expect(build(:account, plan: "free").free?).to be true
      expect(build(:account, plan: "free").pro?).to be false
    end

    it "returns true for pro plan" do
      expect(build(:account, plan: "pro").pro?).to be true
      expect(build(:account, plan: "pro").free?).to be false
    end
  end
end
