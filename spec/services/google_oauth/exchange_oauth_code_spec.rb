# frozen_string_literal: true

require "rails_helper"

RSpec.describe GoogleOauth::ExchangeOauthCode do
  let(:token) do
    GoogleOauth::OauthToken.new(
      access_token:  "ya29.access",
      refresh_token: "1//refresh",
      expires_at:    1.hour.from_now
    )
  end
  let(:oauth) { instance_double(GoogleOauth::OauthAdapter) }

  describe ".call" do
    context "when the exchange succeeds" do
      before { allow(oauth).to receive(:exchange_code).with(code: "valid_code").and_return(token) }

      it "returns Success with the token" do
        result = described_class.call(code: "valid_code", oauth: oauth)
        expect(result).to be_success
        expect(result.value!).to eq(token)
      end
    end

    context "when the exchange raises Signet::AuthorizationError" do
      before { allow(oauth).to receive(:exchange_code).and_raise(Signet::AuthorizationError, "invalid grant") }

      it "returns Failure(:authorization_failed)" do
        result = described_class.call(code: "bad_code", oauth: oauth)
        expect(result).to be_failure.and(have_attributes(failure: :authorization_failed))
      end
    end

    context "when the exchange raises Google::Apis::AuthorizationError" do
      before { allow(oauth).to receive(:exchange_code).and_raise(Google::Apis::AuthorizationError, "unauthorized") }

      it "returns Failure(:authorization_failed)" do
        result = described_class.call(code: "bad_code", oauth: oauth)
        expect(result).to be_failure.and(have_attributes(failure: :authorization_failed))
      end
    end

    context "when an unexpected error occurs" do
      before { allow(oauth).to receive(:exchange_code).and_raise(RuntimeError, "network error") }

      it "returns Failure(:exchange_failed)" do
        result = described_class.call(code: "any_code", oauth: oauth)
        expect(result).to be_failure.and(have_attributes(failure: :exchange_failed))
      end
    end
  end
end
