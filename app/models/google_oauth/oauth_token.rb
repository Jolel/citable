# frozen_string_literal: true

module GoogleOauth
  OauthToken = Data.define(:access_token, :refresh_token, :expires_at)
end
