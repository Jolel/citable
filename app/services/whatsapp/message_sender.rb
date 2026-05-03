# frozen_string_literal: true

module Whatsapp
  class MessageSender
    include Dry::Monads[:result]

    def self.call(...) = new.call(...)

    def call(account:, to:, body:, booking: nil, customer: nil, kind: nil, client: nil)
      return Failure(:credentials_missing) unless client || credentials_present?

      claimed = Account.where(id: account.id)
                       .where("whatsapp_quota_used < ?", account.whatsapp_quota_limit)
                       .update_all("whatsapp_quota_used = whatsapp_quota_used + 1")

      if claimed.zero?
        account.reload
        return Failure(:quota_exceeded)
      end

      account.reload

      begin
        message = deliver(to:, body:, client:)
      rescue Twilio::REST::RestError => e
        release_quota(account)
        log_message(account:, booking:, customer:, body:, kind:, status: "failed")
        if e.status_code == 429
          Rails.logger.warn "[Whatsapp::MessageSender] Twilio daily limit reached: #{e.message}"
          return Failure(:twilio_daily_limit_exceeded)
        end
        Rails.logger.error "[Whatsapp::MessageSender] Twilio error: #{e.message}"
        return Failure(:twilio_error)
      rescue Twilio::REST::TwilioError => e
        release_quota(account)
        log_message(account:, booking:, customer:, body:, kind:, status: "failed")
        Rails.logger.error "[Whatsapp::MessageSender] Twilio error: #{e.message}"
        return Failure(:twilio_error)
      end

      log = log_message(account:, booking:, customer:, body:, kind:, status: "sent", external_id: message&.sid)
      Success(log)
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

    def release_quota(account)
      Account.where(id: account.id)
             .where("whatsapp_quota_used > 0")
             .update_all("whatsapp_quota_used = whatsapp_quota_used - 1")
      account.reload
    end

    def log_message(account:, body:, status:, kind: nil, booking: nil, customer: nil, external_id: nil)
      MessageLog.create!(
        account:, booking:, customer:,
        channel: "whatsapp", direction: "outbound",
        body:, status:, external_id:, kind: kind&.to_s
      )
    end
  end
end
