# frozen_string_literal: true

module TwilioWebhook
  class HandleReply
    include Dry::Monads[:result]

    def self.call(...) = new.call(...)

    def call(from:, to:, body:, profile_name: nil)
      @body = body.to_s.strip
      @from_phone = Account.normalize_whatsapp_number(from)
      @account = Account.find_by(whatsapp_number: Account.normalize_whatsapp_number(to))
      return Success(:account_not_found) unless account

      @customer = find_customer
      conversation = active_conversation

      if conversation
        log_inbound(customer: conversation.customer)
        return AdvanceConversation.call(conversation: conversation, body: @body, account: account, from_phone: from_phone)
      end

      if customer
        booking = resolve_reply_booking(customer)
        if booking
          log_inbound(customer: customer, booking: booking)
          return ProcessBookingReply.call(booking: booking, body: @body)
        end
      end

      log_inbound(customer: customer)
      StartConversation.call(account: account, from_phone: from_phone, customer: customer, profile_name: profile_name.presence)
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error "[TwilioWebhook::HandleReply] #{e.message}"
      Failure(:record_invalid)
    rescue StandardError => e
      Rails.logger.error "[TwilioWebhook::HandleReply] Error processing reply from #{from}: #{e.message}"
      Failure(:processing_error)
    end

    private

    attr_reader :account, :body, :customer, :from_phone

    def active_conversation
      account.whatsapp_conversations.active.open.find_by(from_phone: from_phone)
    end

    def find_customer
      account.customers.find_by("regexp_replace(phone, '[^0-9]', '', 'g') = ?", from_phone)
    end

    REPLY_BINDING_WINDOW = 36.hours

    # Bind a "1" / "2" reply to the booking the business actually messaged
    # (looked up via the most recent outbound prompt MessageLog) rather than
    # whatever booking sorts earliest by starts_at — which is the audit's
    # planted-booking hijack vector.
    def resolve_reply_booking(customer)
      recent_id = account.message_logs
                         .reply_prompts
                         .where(customer: customer, direction: "outbound")
                         .where("created_at > ?", REPLY_BINDING_WINDOW.ago)
                         .order(created_at: :desc)
                         .limit(1)
                         .pick(:booking_id)

      if recent_id
        return account.bookings.active.find_by(id: recent_id)
      end

      active = customer.bookings.active.upcoming.to_a
      active.size == 1 ? active.first : nil
    end

    def log_inbound(customer: nil, booking: nil)
      MessageLog.create!(
        account: account,
        customer: customer,
        booking: booking,
        channel: "whatsapp",
        direction: "inbound",
        body: body,
        status: "delivered"
      )
    end
  end
end
