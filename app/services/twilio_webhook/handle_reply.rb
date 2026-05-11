# frozen_string_literal: true

module TwilioWebhook
  class HandleReply
    include Dry::Monads[:result]

    def self.call(...) = new.call(...)

    def call(from:, to:, body:, profile_name: nil)
      body = body.to_s.strip
      from_phone = Account.normalize_whatsapp_number(from)
      to_phone = Account.normalize_whatsapp_number(to)
      account = Account.find_by(whatsapp_number: to_phone)

      unless account
        Rails.logger.warn "[TwilioWebhook::HandleReply] No account for WhatsApp number #{to_phone}"
        return Success(:account_not_found)
      end

      customer = find_customer(account:, from_phone:)
      conversation = active_conversation(account:, from_phone:)

      if conversation
        Rails.logger.info "[TwilioWebhook::HandleReply] account=#{account.id} phone=#{from_phone} branch=advance_conversation step=#{conversation.step}"
        log_inbound(account:, customer: conversation.customer, body:)
        return AdvanceConversation.call(conversation:, body:, account:, from_phone:)
      end

      if customer
        booking = customer.bookings.active.upcoming.first
        if booking
          Rails.logger.info "[TwilioWebhook::HandleReply] account=#{account.id} phone=#{from_phone} branch=process_booking_reply booking_id=#{booking.id}"
          log_inbound(account:, customer:, booking:, body:)
          return ProcessBookingReply.call(
            booking:    booking,
            body:,
            account:,
            from_phone:,
            customer:
          )
        end
      end

      Rails.logger.info "[TwilioWebhook::HandleReply] account=#{account.id} phone=#{from_phone} branch=start_conversation customer=#{customer&.id || "new"}"
      log_inbound(account:, customer:, body:)
      StartConversation.call(account:, from_phone:, customer:, profile_name: profile_name.presence, body:)
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error "[TwilioWebhook::HandleReply] #{e.message}"
      Failure(:record_invalid)
    rescue StandardError => e
      Rails.logger.error "[TwilioWebhook::HandleReply] Error processing reply from #{from}: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      Failure(:processing_error)
    end

    private

    def find_customer(account:, from_phone:)
      account.customers.find_by("regexp_replace(phone, '[^0-9]', '', 'g') = ?", from_phone)
    end

    def active_conversation(account:, from_phone:)
      account.whatsapp_conversations.active.open.find_by(from_phone:)
    end

    def log_inbound(account:, customer: nil, booking: nil, body:)
      account.message_logs.create!(
        customer:,
        booking:,
        channel: "whatsapp",
        direction: "inbound",
        body:,
        status: "delivered"
      )
    end
  end
end
