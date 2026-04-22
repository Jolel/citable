# frozen_string_literal: true

module TwilioWebhook
  class HandleReply
    include Dry::Monads[:result]

    def self.call(...) = new.call(...)

    def call(from:, body:)
      customer = find_customer(from)
      return Success(:customer_not_found) unless customer

      booking = customer.bookings.active.upcoming.first
      return Success(:no_upcoming_booking) unless booking

      log_inbound(customer, booking, body)
      process_reply(booking, body)

      Success(booking)
    rescue StandardError => e
      Rails.logger.error "[TwilioWebhook::HandleReply] Error processing reply from #{from}: #{e.message}"
      Failure(:processing_error)
    end

    private

    def find_customer(from)
      digits = from.gsub(/\D/, "").last(10)
      Customer.find_by("phone LIKE ?", "%#{digits}%")
    end

    def log_inbound(customer, booking, body)
      MessageLog.create!(
        account:   customer.account,
        customer:  customer,
        booking:   booking,
        channel:   "whatsapp",
        direction: "inbound",
        body:      body,
        status:    "delivered"
      )
    end

    def process_reply(booking, body)
      case body
      when "1" then booking.confirm!
      when "2" then booking.cancel!
      end
    end
  end
end
