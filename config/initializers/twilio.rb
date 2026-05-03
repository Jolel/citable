# frozen_string_literal: true

# Boot-time assertion: production must have a Twilio auth token in
# credentials. Without it, signed webhook validation degrades to HMAC-SHA1
# against an empty key — trivially forgeable.
if Rails.env.production? && Rails.application.credentials.dig(:twilio, :auth_token).blank?
  raise "TWILIO_AUTH_TOKEN missing — refusing to boot production without a Twilio webhook secret."
end
