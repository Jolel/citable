# frozen_string_literal: true

require "rails_helper"

RSpec.describe User, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to have_many(:staff_availabilities).dependent(:destroy) }
    it { is_expected.to have_many(:bookings).dependent(:restrict_with_error) }
  end

  describe "validations" do
    subject { build(:user) }

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:role) }
    it { is_expected.to validate_presence_of(:email) }
  end

  describe "enums" do
    it "has the expected role values" do
      expect(User.roles).to eq("owner" => "owner", "staff" => "staff")
    end
  end

  describe "scopes" do
    let(:account) { create(:account) }
    let!(:owner) { create(:user, :owner, account: account) }
    let!(:staff) { create(:user, account: account) }
    let!(:google_user) { create(:user, :google_connected, account: account) }

    describe ".owners" do
      it "returns only owners" do
        expect(account.users.owners).to contain_exactly(owner)
      end
    end

    describe ".staff_members" do
      it "returns only staff-role users" do
        expect(account.users.staff_members).to contain_exactly(staff, google_user)
      end
    end

    describe ".google_connected" do
      it "returns users with a google token" do
        expect(account.users.google_connected).to contain_exactly(google_user)
      end
    end
  end

  describe "#google_connected?" do
    it "returns false when no token" do
      user = build(:user)
      expect(user.google_connected?).to be false
    end

    it "returns true when token is present" do
      user = build(:user, :google_connected)
      expect(user.google_connected?).to be true
    end
  end

  describe "#google_token_expired?" do
    it "returns false when expiry is in the future" do
      user = build(:user, google_token_expires_at: 1.hour.from_now)
      expect(user.google_token_expired?).to be false
    end

    it "returns true when expiry is within 5 minutes" do
      user = build(:user, google_token_expires_at: 2.minutes.from_now)
      expect(user.google_token_expired?).to be true
    end

    it "returns true when expiry is in the past" do
      user = build(:user, google_token_expires_at: 1.hour.ago)
      expect(user.google_token_expired?).to be true
    end

    it "returns false when no expiry set" do
      user = build(:user, google_token_expires_at: nil)
      expect(user.google_token_expired?).to be false
    end
  end

  describe "#google_watch_expiring?" do
    it "returns true when channel expires within 1 day" do
      user = build(:user, google_channel_expires_at: 12.hours.from_now)
      expect(user.google_watch_expiring?).to be true
    end

    it "returns false when channel expires in more than 1 day" do
      user = build(:user, google_channel_expires_at: 2.days.from_now)
      expect(user.google_watch_expiring?).to be false
    end

    it "returns false when no channel set" do
      user = build(:user, google_channel_expires_at: nil)
      expect(user.google_watch_expiring?).to be false
    end
  end

  describe "#disconnect_google!" do
    it "clears all google fields" do
      user = create(:user, :google_connected)
      user.disconnect_google!
      expect(user.reload.google_oauth_token).to be_nil
      expect(user.google_refresh_token).to be_nil
      expect(user.google_token_expires_at).to be_nil
      expect(user.google_calendar_id).to be_nil
    end
  end

  describe "#display_name" do
    it "returns name when present" do
      user = build(:user, name: "Ana García")
      expect(user.display_name).to eq("Ana García")
    end

    it "falls back to email when name is blank" do
      user = build(:user, name: "")
      expect(user.display_name).to eq(user.email)
    end
  end
end
