# frozen_string_literal: true

module GoogleOauth
  class VerifyStateToken
    include Dry::Monads[:result]

    MAX_STATE_AGE = 10.minutes

    def self.call(...)
      new.call(...)
    end

    def call(signed_state)
      payload_b64, _, signature = signed_state.to_s.rpartition(".")

      unless ActiveSupport::SecurityUtils.secure_compare(signature.to_s, sign(payload_b64))
        return Failure(:invalid_state)
      end

      data = JSON.parse(Base64.strict_decode64(payload_b64))
      iat  = data["iat"]

      if iat.is_a?(Integer) && Time.now.to_i - iat > MAX_STATE_AGE.to_i
        return Failure(:state_expired)
      end

      Success(
        user_id:      data["user_id"],
        return_to:    data["return_to"],
        initiator_id: data["initiator_id"],
        nonce:        data["nonce"],
        iat:          iat
      )
    rescue ArgumentError, JSON::ParserError => e
      Rails.logger.error "[GoogleOauth::VerifyStateToken] #{e.message}"
      Failure(:invalid_state)
    end

    private

    def sign(payload)
      OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, payload)
    end
  end
end
