# frozen_string_literal: true

module GoogleOauth
  class BuildStateToken
    include Dry::Monads[:result]

    def self.call(...)
      new.call(...)
    end

    def call(user_id:, return_to:)
      payload   = Base64.strict_encode64(JSON.generate(user_id: user_id, return_to: return_to))
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
