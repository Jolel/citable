# frozen_string_literal: true

require "webmock/rspec"

# Allow Selenium/browser connections; block all other external HTTP.
WebMock.disable_net_connect!(allow_localhost: true)

RSpec.configure do |config|
  config.before(:each) do
    # Stub outbound Twilio WhatsApp messages so specs don't need real credentials.
    stub_request(:post, /api\.twilio\.com.*Messages\.json/)
      .to_return(status: 200, body: { sid: "SM_test", status: "queued" }.to_json,
                 headers: { "Content-Type" => "application/json" })
  end
end
