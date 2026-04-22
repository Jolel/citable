# frozen_string_literal: true

module GoogleOauth
  class PersistOauthToken
    include Dry::Monads[:result]

    def self.call(...) = new.call(...)

    def call(user:, token:)
      user.update!(
        google_oauth_token:      token.access_token,
        google_refresh_token:    token.refresh_token,
        google_token_expires_at: token.expires_at
      )
      Success(user.reload)
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error "[GoogleOauth::PersistOauthToken] #{e.message}"
      Failure(:token_persistence_failed)
    end
  end
end
