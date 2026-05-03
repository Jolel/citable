# frozen_string_literal: true

require "rails_helper"

RSpec.describe GoogleOauth::BuildAuthorizationUrl do
  let(:user_id)      { 1 }
  let(:initiator_id) { 1 }
  let(:nonce)        { "n0nc3" }
  let(:redirect_uri) { "https://app.example.com/oauth/callback" }
  let(:base_args) do
    { user_id: user_id, redirect_uri: redirect_uri, initiator_id: initiator_id, nonce: nonce }
  end

  describe ".call" do
    context "with a stub oauth adapter" do
      let(:fake_url) { "https://accounts.google.com/o/oauth2/auth?state=abc" }
      let(:oauth)    { instance_double(GoogleOauth::OauthAdapter, authorization_uri: fake_url) }

      it "returns Success with the authorization URL" do
        result = described_class.call(**base_args, oauth: oauth)
        expect(result).to be_success
        expect(result.value!).to eq(fake_url)
      end

      it "passes state, scopes to the oauth adapter" do
        expect(oauth).to receive(:authorization_uri)
          .with(hash_including(scopes: GoogleOauth::BuildAuthorizationUrl::SCOPES))
          .and_return(fake_url)
        described_class.call(**base_args, oauth: oauth)
      end
    end

    context "when BuildStateToken fails" do
      before { allow(GoogleOauth::BuildStateToken).to receive(:call).and_return(Dry::Monads::Failure(:state_token_build_failed)) }

      it "propagates the failure" do
        result = described_class.call(**base_args)
        expect(result).to be_failure
      end
    end

    context "when the oauth adapter raises KeyError (missing credentials)" do
      let(:oauth) { instance_double(GoogleOauth::OauthAdapter) }

      before { allow(oauth).to receive(:authorization_uri).and_raise(KeyError, "google") }

      it "returns Failure(:missing_credentials)" do
        result = described_class.call(**base_args, oauth: oauth)
        expect(result).to be_failure.and(have_attributes(failure: :missing_credentials))
      end
    end

    context "when the oauth adapter raises an unexpected error" do
      let(:oauth) { instance_double(GoogleOauth::OauthAdapter) }

      before { allow(oauth).to receive(:authorization_uri).and_raise(RuntimeError, "boom") }

      it "returns Failure(:authorization_url_failed)" do
        result = described_class.call(**base_args, oauth: oauth)
        expect(result).to be_failure.and(have_attributes(failure: :authorization_url_failed))
      end
    end
  end
end
