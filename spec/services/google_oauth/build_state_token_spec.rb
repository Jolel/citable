# frozen_string_literal: true

require "rails_helper"

RSpec.describe GoogleOauth::BuildStateToken do
  describe ".call" do
    let(:user_id)   { 42 }
    let(:return_to) { "/dashboard" }

    it "returns a Success with a signed token" do
      result = described_class.call(user_id: user_id, return_to: return_to)
      expect(result).to be_success
    end

    it "encodes user_id and return_to in the payload" do
      token = described_class.call(user_id: user_id, return_to: return_to).value!
      payload_b64 = token.split(".").first
      data = JSON.parse(Base64.strict_decode64(payload_b64))
      expect(data).to eq("user_id" => user_id, "return_to" => return_to)
    end

    it "appends a valid HMAC signature" do
      token = described_class.call(user_id: user_id, return_to: return_to).value!
      payload_b64, _, signature = token.rpartition(".")
      expected = OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, payload_b64)
      expect(signature).to eq(expected)
    end

    it "produces different tokens for different user_ids" do
      t1 = described_class.call(user_id: 1, return_to: return_to).value!
      t2 = described_class.call(user_id: 2, return_to: return_to).value!
      expect(t1).not_to eq(t2)
    end
  end
end
