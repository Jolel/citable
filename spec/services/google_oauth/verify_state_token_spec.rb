# frozen_string_literal: true

require "rails_helper"

RSpec.describe GoogleOauth::VerifyStateToken do
  def build_token(user_id:, return_to:, initiator_id: 1, nonce: "n0nc3")
    GoogleOauth::BuildStateToken.call(
      user_id: user_id, return_to: return_to,
      initiator_id: initiator_id, nonce: nonce
    ).value!
  end

  describe ".call" do
    it "returns Success with user_id, return_to, initiator_id, nonce, iat for a valid token" do
      token = build_token(user_id: 7, return_to: "/dashboard", initiator_id: 3, nonce: "abc")
      result = described_class.call(token)
      expect(result).to be_success
      data = result.value!
      expect(data).to include(user_id: 7, return_to: "/dashboard", initiator_id: 3, nonce: "abc")
      expect(data[:iat]).to be_a(Integer)
    end

    it "returns Failure(:invalid_state) when signature is tampered" do
      token = build_token(user_id: 7, return_to: "/dashboard")
      bad_token = "#{token}tampered"
      expect(described_class.call(bad_token)).to be_failure.and(have_attributes(failure: :invalid_state))
    end

    it "returns Failure(:invalid_state) when payload is replaced" do
      _, signature = build_token(user_id: 7, return_to: "/dashboard").split(".", 2)
      evil_payload = Base64.strict_encode64(JSON.generate(user_id: 99, return_to: "/admin"))
      expect(described_class.call("#{evil_payload}.#{signature}")).to be_failure
    end

    it "returns Failure(:state_expired) when iat is older than the max age" do
      token = build_token(user_id: 7, return_to: "/dashboard")
      travel_to(Time.now + GoogleOauth::VerifyStateToken::MAX_STATE_AGE + 1.minute) do
        expect(described_class.call(token)).to be_failure.and(have_attributes(failure: :state_expired))
      end
    end

    it "returns Failure(:invalid_state) for a blank string" do
      expect(described_class.call("")).to be_failure.and(have_attributes(failure: :invalid_state))
    end

    it "returns Failure(:invalid_state) for nil" do
      expect(described_class.call(nil)).to be_failure.and(have_attributes(failure: :invalid_state))
    end

    it "returns Failure(:invalid_state) for a non-base64 payload" do
      expect(described_class.call("!!!.badsig")).to be_failure.and(have_attributes(failure: :invalid_state))
    end
  end
end
