require "google/apis/calendar_v3"
require "googleauth"

class GoogleCalendarSyncJob < ApplicationJob
  queue_as :default

  retry_on Google::Apis::ServerError, Google::Apis::RateLimitError, wait: :polynomially_longer, attempts: 3

  def perform(booking_id, action)
    booking = Booking.find_by(id: booking_id)
    return unless booking

    ActsAsTenant.with_tenant(booking.account) do
      staff = booking.user
      return unless staff.google_connected?

      GoogleCalendarService.new(staff).sync_booking(booking, action.to_sym)
    end
  end
end
