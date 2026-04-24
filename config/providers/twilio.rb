# frozen_string_literal: true

Citable::Container.register_provider(:twilio) do
  prepare do
    require "twilio-ruby"
  end

  start do
    creds = Rails.application.credentials.twilio!

    register("twilio.client",      Twilio::REST::Client.new(creds.account_sid, creds.auth_token))
    register("twilio.from_number", creds.whatsapp_number)
  end
end
