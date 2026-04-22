# frozen_string_literal: true

class Webhooks::TwilioController < ActionController::Base
  skip_forgery_protection
  before_action :verify_twilio_signature

  TWILIO_AUTH_TOKEN = Rails.application.credentials.dig(:twilio, :auth_token)

  def create
    TwilioWebhook::HandleReply.call(
      from: params[:From],
      body: params[:Body]&.strip
    )

    head :ok
  end

  private

  def verify_twilio_signature
    validator = Twilio::Security::RequestValidator.new(TWILIO_AUTH_TOKEN)
    signature = request.env["HTTP_X_TWILIO_SIGNATURE"].to_s
    return if validator.validate(request.url, params.to_unsafe_h, signature)

    head :forbidden
  end
end
