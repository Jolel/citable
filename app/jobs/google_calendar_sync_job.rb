class GoogleCalendarSyncJob < ApplicationJob
  queue_as :default

  def perform(booking_id)
    booking = Booking.find_by(id: booking_id)
    return unless booking

    ActsAsTenant.with_tenant(booking.account) do
      staff = booking.user
      return unless staff.google_connected?

      if booking.google_event_id.present?
        update_event(booking, staff)
      else
        create_event(booking, staff)
      end
    end
  end

  private

  def create_event(booking, staff)
    # TODO: implement Google Calendar API call
    # Requires google-api-ruby-client gem and OAuth2 token refresh logic
    Rails.logger.info "[GoogleCalendarSyncJob] Would create event for booking #{booking.id}"
  end

  def update_event(booking, staff)
    Rails.logger.info "[GoogleCalendarSyncJob] Would update event #{booking.google_event_id} for booking #{booking.id}"
  end
end
