# frozen_string_literal: true

module GoogleOauth
  class ExchangeOauthCode
    include Dry::Monads[:result]

    def self.call(...) = new.call(...)

    def call(code:, oauth:)
      token = oauth.exchange_code(code: code)
      Success(token)
    rescue Signet::AuthorizationError, Google::Apis::AuthorizationError => e
      Rails.logger.error "[GoogleOauth::ExchangeOauthCode] #{e.message}"
      Failure(:authorization_failed)
    rescue StandardError => e
      Rails.logger.error "[GoogleOauth::ExchangeOauthCode] #{e.message}"
      Failure(:exchange_failed)
    end
  end
end
