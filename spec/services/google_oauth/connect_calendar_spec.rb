# frozen_string_literal: true

require "rails_helper"

RSpec.describe GoogleOauth::ConnectCalendar do
  let(:user)         { create(:user) }
  let(:redirect_uri) { "https://app.example.com/oauth/callback" }
  let(:code)         { "auth_code_123" }
  let(:token) do
    GoogleOauth::OauthToken.new(
      access_token:  "ya29.access",
      refresh_token: "1//refresh",
      expires_at:    1.hour.from_now
    )
  end
  let(:oauth) { instance_double(GoogleOauth::OauthAdapter) }

  before do
    allow(oauth).to receive(:exchange_code).with(code: code).and_return(token)
  end

  describe ".call" do
    context "when exchange and persist succeed and no webhook_url" do
      let(:calendar) { instance_double(GoogleOauth::CalendarAdapter, ensure_calendar: nil) }

      before do
        allow(GoogleOauth::CalendarAdapter).to receive(:new).and_return(calendar)
      end

      it "returns Success with the updated user" do
        result = described_class.call(user: user, code: code, redirect_uri: redirect_uri, oauth: oauth)
        expect(result).to be_success
        expect(result.value!).to be_a(User)
      end

      it "stores the access token on the user" do
        described_class.call(user: user, code: code, redirect_uri: redirect_uri, oauth: oauth)
        expect(user.reload.google_oauth_token).to eq("ya29.access")
      end
    end

    context "when webhook_url is provided" do
      let(:webhook_url) { "https://app.example.com/webhooks/google_calendar" }
      let(:calendar)    { instance_double(GoogleOauth::CalendarAdapter, ensure_calendar: nil, setup_watch: nil) }

      before do
        allow(GoogleOauth::CalendarAdapter).to receive(:new).and_return(calendar)
      end

      it "calls setup_watch with the webhook_url" do
        expect(calendar).to receive(:setup_watch).with(webhook_url)
        described_class.call(user: user, code: code, redirect_uri: redirect_uri, webhook_url: webhook_url, oauth: oauth)
      end
    end

    context "when ExchangeOauthCode fails" do
      before do
        allow(oauth).to receive(:exchange_code).and_raise(Signet::AuthorizationError, "invalid grant")
      end

      it "returns Failure(:authorization_failed)" do
        result = described_class.call(user: user, code: code, redirect_uri: redirect_uri, oauth: oauth)
        expect(result).to be_failure.and(have_attributes(failure: :authorization_failed))
      end
    end

    context "when calendar setup raises an error" do
      let(:calendar) { instance_double(GoogleOauth::CalendarAdapter) }

      before do
        allow(GoogleOauth::CalendarAdapter).to receive(:new).and_return(calendar)
        allow(calendar).to receive(:ensure_calendar).and_raise(RuntimeError, "Google API error")
      end

      it "returns Failure(:calendar_setup_failed)" do
        result = described_class.call(user: user, code: code, redirect_uri: redirect_uri, oauth: oauth)
        expect(result).to be_failure.and(have_attributes(failure: :calendar_setup_failed))
      end
    end
  end
end
