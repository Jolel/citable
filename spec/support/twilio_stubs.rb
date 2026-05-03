# frozen_string_literal: true

# Globally stub Twilio credentials and the REST client for all specs so that
# Whatsapp::MessageSender (which now fails closed when credentials are
# missing) and Webhooks::TwilioController (which now reads the auth token
# per request and 503s when blank) both behave like a configured deployment
# without needing real secrets in CI.
#
# Specs that want to exercise the credentials-missing path can override
# these stubs locally with `allow(...).to receive(...).and_return(nil)`.
RSpec.configure do |config|
  config.before(:each) do
    twilio_message = double(sid: "SM_test_#{SecureRandom.hex(4)}")
    twilio_messages = double("twilio_messages", create: twilio_message)
    twilio_client = double("twilio_client", messages: twilio_messages)

    allow(Rails.application.credentials).to receive(:dig).and_call_original
    allow(Rails.application.credentials).to receive(:dig)
      .with(:twilio, :account_sid).and_return("AC_TEST_SID")
    allow(Rails.application.credentials).to receive(:dig)
      .with(:twilio, :auth_token).and_return("TEST_AUTH_TOKEN")
    allow(Rails.application.credentials).to receive(:dig)
      .with(:twilio, :whatsapp_number).and_return("14155238886")

    allow(Twilio::REST::Client).to receive(:new).and_return(twilio_client)
  end
end
