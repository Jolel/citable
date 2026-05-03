# frozen_string_literal: true

class Webhooks::TwilioController < ActionController::Base
  skip_forgery_protection
  before_action :verify_twilio_signature

  def create
    TwilioWebhook::HandleReply.call(
      from: params[:From],
      to: params[:To],
      body: params[:Body]&.strip,
      profile_name: params[:ProfileName]
    )

    head :ok
  end

  private

  # Read the auth token from credentials at request time rather than capturing
  # at class load — credential rotation takes effect immediately, and a deploy
  # with a missing token returns 503 instead of computing HMAC-SHA1 against an
  # empty key (which an attacker can replicate trivially).
  def verify_twilio_signature
    token = Rails.application.credentials.dig(:twilio, :auth_token)
    if token.blank?
      Rails.logger.error "[Webhooks::TwilioController] Twilio auth token missing — refusing webhook"
      return head :service_unavailable
    end

    validator = Twilio::Security::RequestValidator.new(token)
    signature = request.env["HTTP_X_TWILIO_SIGNATURE"].to_s
    return if validator.validate(request.url, request.request_parameters, signature)

    head :forbidden
  end
end
