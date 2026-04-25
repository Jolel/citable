# frozen_string_literal: true

module Whatsapp
  class MessageSender
    include Dry::Monads[:result]

    def self.call(...) = new.call(...)

    def call(account:, to:, body:, booking: nil, customer: nil, client: nil)
      return Failure(:quota_exceeded) if account.whatsapp_quota_exceeded?

      message = deliver(to:, body:, client:)
      log = log_message(account:, booking:, customer:, body:, status: "sent", external_id: message&.sid)
      account.increment!(:whatsapp_quota_used)
      Success(log)
    rescue Twilio::REST::RestError => e
      if e.status_code == 429
        Rails.logger.warn "[Whatsapp::MessageSender] Twilio daily limit reached: #{e.message}"
        log_message(account:, booking:, customer:, body:, status: "failed")
        Failure(:twilio_daily_limit_exceeded)
      else
        Rails.logger.error "[Whatsapp::MessageSender] Twilio error: #{e.message}"
        log_message(account:, booking:, customer:, body:, status: "failed")
        Failure(:twilio_error)
      end
    rescue Twilio::REST::TwilioError => e
      Rails.logger.error "[Whatsapp::MessageSender] Twilio error: #{e.message}"
      log_message(account:, booking:, customer:, body:, status: "failed")
      Failure(:twilio_error)
    end

    private

    def deliver(to:, body:, client:)
      return unless client || credentials_present?

      (client || default_client).messages.create(
        from: "whatsapp:#{twilio_from}",
        to:   "whatsapp:+#{Account.normalize_whatsapp_number(to)}",
        body: body
      )
    end

    def default_client
      Twilio::REST::Client.new(twilio_account_sid, twilio_auth_token)
    end

    def credentials_present?
      twilio_account_sid.present? && twilio_auth_token.present? && twilio_from.present?
    end

    def twilio_account_sid = Rails.application.credentials.dig(:twilio, :account_sid)
    def twilio_auth_token  = Rails.application.credentials.dig(:twilio, :auth_token)
    def twilio_from        = Rails.application.credentials.dig(:twilio, :whatsapp_number)

    def log_message(account:, body:, status:, booking: nil, customer: nil, external_id: nil)
      MessageLog.create!(
        account:, booking:, customer:,
        channel: "whatsapp", direction: "outbound",
        body:, status:, external_id:
      )
    end
  end
end
