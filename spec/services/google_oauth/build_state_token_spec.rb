# frozen_string_literal: true

require "rails_helper"

RSpec.describe GoogleOauth::BuildStateToken do
  describe ".call" do
    let(:user_id)      { 42 }
    let(:initiator_id) { 7 }
    let(:return_to)    { "/dashboard" }
    let(:nonce)        { "abc123" }

    let(:args) do
      { user_id: user_id, return_to: return_to, initiator_id: initiator_id, nonce: nonce }
    end

    it "returns a Success with a signed token" do
      result = described_class.call(**args)
      expect(result).to be_success
    end

    it "encodes user_id, return_to, initiator_id, nonce, and iat in the payload" do
      token = described_class.call(**args).value!
      payload_b64 = token.split(".").first
      data = JSON.parse(Base64.strict_decode64(payload_b64))
      expect(data).to include(
        "user_id"      => user_id,
        "return_to"    => return_to,
        "initiator_id" => initiator_id,
        "nonce"        => nonce
      )
      expect(data["iat"]).to be_a(Integer)
    end

    it "appends a valid HMAC signature" do
      token = described_class.call(**args).value!
      payload_b64, _, signature = token.rpartition(".")
      expected = OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, payload_b64)
      expect(signature).to eq(expected)
    end

    it "produces different tokens for different user_ids" do
      t1 = described_class.call(**args.merge(user_id: 1)).value!
      t2 = described_class.call(**args.merge(user_id: 2)).value!
      expect(t1).not_to eq(t2)
    end
  end
end
