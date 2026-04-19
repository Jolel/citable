require "google/apis/calendar_v3"
require "googleauth"

class GoogleCalendarSyncJob < ApplicationJob
  queue_as :default

  retry_on Google::Apis::ServerError, Google::Apis::RateLimitError, wait: :polynomially_longer, attempts: 3

  def perform(booking_id)
    booking = Booking.find_by(id: booking_id)
    return unless booking

    ActsAsTenant.with_tenant(booking.account) do
      staff = booking.user
      return unless staff.google_connected?

      service = build_calendar_service(staff)

      if booking.google_event_id.present?
        update_event(booking, staff, service)
      else
        create_event(booking, staff, service)
      end
    end
  end

  private

  def build_calendar_service(user)
    credentials = Google::Auth::UserRefreshCredentials.new(
      client_id:     Rails.application.credentials.dig(:google, :client_id),
      client_secret: Rails.application.credentials.dig(:google, :client_secret),
      scope:         "https://www.googleapis.com/auth/calendar",
      access_token:  user.google_oauth_token,
      refresh_token: user.google_refresh_token,
      expires_at:    user.google_token_expires_at
    )

    if user.google_token_expired?
      credentials.refresh!
      user.update_columns(
        google_oauth_token:      credentials.access_token,
        google_token_expires_at: Time.at(credentials.expires_at)
      )
    end

    cal = Google::Apis::CalendarV3::CalendarService.new
    cal.authorization = credentials
    cal
  end

  def build_event(booking)
    timezone = booking.account.timezone
    Google::Apis::CalendarV3::Event.new(
      summary:     "#{booking.service.name} — #{booking.customer.name}",
      description: "Cita creada en Citable\nCliente: #{booking.customer.name}\nTeléfono: #{booking.customer.phone}",
      start:       Google::Apis::CalendarV3::EventDateTime.new(
                     date_time: booking.starts_at.in_time_zone(timezone).iso8601,
                     time_zone: timezone
                   ),
      end:         Google::Apis::CalendarV3::EventDateTime.new(
                     date_time: booking.ends_at.in_time_zone(timezone).iso8601,
                     time_zone: timezone
                   ),
      status:      booking.cancelled? ? "cancelled" : "confirmed"
    )
  end

  def create_event(booking, staff, service)
    event = service.insert_event(staff.google_calendar_id, build_event(booking))
    booking.update_columns(google_event_id: event.id)
    Rails.logger.info "[GoogleCalendarSyncJob] Created event #{event.id} for booking #{booking.id}"
  rescue Google::Apis::Error => e
    Rails.logger.error "[GoogleCalendarSyncJob] Failed to create event for booking #{booking.id}: #{e.message}"
    raise
  end

  def update_event(booking, staff, service)
    service.update_event(staff.google_calendar_id, booking.google_event_id, build_event(booking))
    Rails.logger.info "[GoogleCalendarSyncJob] Updated event #{booking.google_event_id} for booking #{booking.id}"
  rescue Google::Apis::ClientError => e
    if e.status_code == 404
      booking.update_columns(google_event_id: nil)
      create_event(booking, staff, service)
    else
      Rails.logger.error "[GoogleCalendarSyncJob] Failed to update event for booking #{booking.id}: #{e.message}"
      raise
    end
  rescue Google::Apis::Error => e
    Rails.logger.error "[GoogleCalendarSyncJob] Failed to update event for booking #{booking.id}: #{e.message}"
    raise
  end
end
