# frozen_string_literal: true

module GoogleOauth
  class BuildAuthorizationUrl
    include Dry::Monads[:result]

    SCOPES = %w[
      https://www.googleapis.com/auth/calendar
      https://www.googleapis.com/auth/calendar.events
    ].freeze

    def self.call(...)
      new.call(...)
    end

    def call(user_id:, redirect_uri:, initiator_id:, nonce:, return_to: nil, oauth: nil)
      BuildStateToken.call(
        user_id:      user_id,
        return_to:    return_to,
        initiator_id: initiator_id,
        nonce:        nonce
      ).bind do |state|
        adapter = oauth || OauthAdapter.new(redirect_uri: redirect_uri)
        uri     = adapter.authorization_uri(state: state, scopes: SCOPES)

        Success(uri)
      end
    rescue KeyError => e
      Rails.logger.error "[GoogleOauth::BuildAuthorizationUrl] Missing credentials: #{e.message}"
      Failure(:missing_credentials)
    rescue StandardError => e
      Rails.logger.error "[GoogleOauth::BuildAuthorizationUrl] #{e.message}"
      Failure(:authorization_url_failed)
    end
  end
end
