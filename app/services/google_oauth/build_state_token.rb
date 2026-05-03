# frozen_string_literal: true

module GoogleOauth
  class BuildStateToken
    include Dry::Monads[:result]

    def self.call(...)
      new.call(...)
    end

    # Bind the OAuth state token to the initiating session so the Google
    # callback cannot be completed by a different user. iat lets the verifier
    # reject stale tokens; nonce binds to a session-scoped value the
    # callback re-checks against the user's session.
    def call(user_id:, return_to:, initiator_id:, nonce:)
      payload = Base64.strict_encode64(JSON.generate(
        user_id:      user_id,
        return_to:    return_to,
        initiator_id: initiator_id,
        nonce:        nonce,
        iat:          Time.now.to_i
      ))
      signature = sign(payload)

      Success("#{payload}.#{signature}")
    rescue StandardError => e
      Rails.logger.error "[GoogleOauth::BuildStateToken] #{e.message}"
      Failure(:state_token_build_failed)
    end

    private

    def sign(payload)
      OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, payload)
    end
  end
end
