# frozen_string_literal: true

module TwilioWebhook
  class ProcessBookingReply
    include Dry::Monads[:result]

    def self.call(...) = new.call(...)

    def call(booking:, body:)
      case body
      when "1" then booking.confirm!
      when "2" then booking.cancel!
      end
      Success(booking)
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error "[TwilioWebhook::ProcessBookingReply] #{e.message}"
      Failure(:booking_update_failed)
    end
  end
end
