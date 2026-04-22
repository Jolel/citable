# frozen_string_literal: true

require "rails_helper"

RSpec.describe GoogleOauth::PersistOauthToken do
  let(:user)       { create(:user) }
  let(:expires_at) { 1.hour.from_now.change(usec: 0) }
  let(:token) do
    GoogleOauth::OauthToken.new(
      access_token:  "ya29.new_access",
      refresh_token: "1//new_refresh",
      expires_at:    expires_at
    )
  end

  describe ".call" do
    it "returns Success with the reloaded user" do
      result = described_class.call(user: user, token: token)
      expect(result).to be_success
      expect(result.value!).to be_a(User)
    end

    it "persists the access token" do
      described_class.call(user: user, token: token)
      expect(user.reload.google_oauth_token).to eq("ya29.new_access")
    end

    it "persists the refresh token" do
      described_class.call(user: user, token: token)
      expect(user.reload.google_refresh_token).to eq("1//new_refresh")
    end

    it "persists the token expiry" do
      described_class.call(user: user, token: token)
      expect(user.reload.google_token_expires_at).to be_within(1.second).of(expires_at)
    end

    context "when update! raises ActiveRecord::RecordInvalid" do
      before { allow(user).to receive(:update!).and_raise(ActiveRecord::RecordInvalid.new(user)) }

      it "returns Failure(:token_persistence_failed)" do
        result = described_class.call(user: user, token: token)
        expect(result).to be_failure.and(have_attributes(failure: :token_persistence_failed))
      end
    end
  end
end
