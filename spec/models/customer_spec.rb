# frozen_string_literal: true

require "rails_helper"

RSpec.describe Customer, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to have_many(:bookings).dependent(:destroy) }
    it { is_expected.to have_many(:message_logs).dependent(:destroy) }
  end

  describe "validations" do
    subject { build(:customer) }

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:phone) }

    context "phone format" do
      it "accepts valid mexican phone with country code" do
        expect(build(:customer, phone: "+5215512345678")).to be_valid
      end

      it "accepts phone with spaces and parentheses" do
        expect(build(:customer, phone: "+52 (55) 1234-5678")).to be_valid
      end

      it "rejects phone with letters" do
        expect(build(:customer, phone: "phone-abc")).not_to be_valid
      end

      it "rejects empty phone" do
        expect(build(:customer, phone: "")).not_to be_valid
      end
    end
  end

  describe "scopes" do
    let(:account) { create(:account) }
    let!(:vip_customer) { create(:customer, account: account, tags: ["vip", "regular"]) }
    let!(:regular_customer) { create(:customer, account: account, tags: ["regular"]) }
    let!(:new_customer) { create(:customer, account: account, tags: []) }

    describe ".with_tag" do
      it "returns customers having the given tag" do
        expect(account.customers.with_tag("vip")).to contain_exactly(vip_customer)
      end

      it "returns multiple customers sharing a tag" do
        expect(account.customers.with_tag("regular")).to contain_exactly(vip_customer, regular_customer)
      end

      it "returns empty when no customer has the tag" do
        expect(account.customers.with_tag("nonexistent")).to be_empty
      end
    end

    describe ".by_name" do
      it "orders customers alphabetically by name" do
        a = create(:customer, account: account, name: "Ana")
        b = create(:customer, account: account, name: "Beatriz")
        expect(account.customers.by_name.to_a.first(2)).to eq([a, b])
      end
    end
  end

  describe "#normalized_phone" do
    it "strips non-digit characters" do
      customer = build(:customer, phone: "+52 (55) 1234-5678")
      expect(customer.normalized_phone).to eq("525512345678")
    end
  end

  describe "#upcoming_bookings and #past_bookings" do
    before do
      allow(GoogleCalendarSyncJob).to receive(:perform_later)
      allow(ReminderJob).to receive(:set).and_return(double(perform_later: true))
    end

    let(:account) { create(:account) }
    let(:customer) { create(:customer, account: account) }
    let(:user) { create(:user, account: account) }
    let(:service) { create(:service, account: account) }

    let!(:future_booking) do
      create(:booking, account: account, customer: customer, user: user, service: service,
             starts_at: 2.days.from_now)
    end
    let!(:past_booking) do
      create(:booking, :past, account: account, customer: customer, user: user, service: service)
    end

    it "upcoming_bookings returns only future bookings" do
      expect(customer.upcoming_bookings).to include(future_booking)
      expect(customer.upcoming_bookings).not_to include(past_booking)
    end

    it "past_bookings returns only past bookings" do
      expect(customer.past_bookings).to include(past_booking)
      expect(customer.past_bookings).not_to include(future_booking)
    end
  end
end
