# frozen_string_literal: true

module GoogleOauth
  class OauthAdapter
    AUTHORIZATION_URI    = "https://accounts.google.com/o/oauth2/auth"
    TOKEN_CREDENTIAL_URI = "https://oauth2.googleapis.com/token"

    def initialize(redirect_uri:)
      @redirect_uri = redirect_uri
    end

    def authorization_uri(state:, scopes:)
      client = build_client
      client.state = state
      client.update!(
        scope:                  scopes,
        access_type:            "offline",
        include_granted_scopes: "true",
        prompt:                 "consent"
      )
      client.authorization_uri.to_s
    end

    def exchange_code(code:)
      client = build_client
      client.code = code
      client.fetch_access_token!
      OauthToken.new(
        access_token:  client.access_token,
        refresh_token: client.refresh_token,
        expires_at:    client.expires_at
      )
    end

    private

    def build_client
      Signet::OAuth2::Client.new(
        client_id:            credentials.client_id,
        client_secret:        credentials.client_secret,
        authorization_uri:    AUTHORIZATION_URI,
        token_credential_uri: TOKEN_CREDENTIAL_URI,
        redirect_uri:         credentials.redirect_uri || @redirect_uri
      )
    end

    def credentials
      Rails.application.credentials.google!
    end
  end
end
