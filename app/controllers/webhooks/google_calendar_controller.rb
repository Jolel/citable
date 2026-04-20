# frozen_string_literal: true

class Webhooks::GoogleCalendarController < ActionController::Base
  protect_from_forgery with: :null_session

  # POST /webhooks/google_calendar
  def receive
    expected_token = Rails.application.credentials.google&.webhook_token
    received_token = request.headers["X-Goog-Channel-Token"]

    unless expected_token.present? &&
           ActiveSupport::SecurityUtils.secure_compare(received_token.to_s, expected_token.to_s)
      head :ok and return
    end

    channel_id = request.headers["X-Goog-Channel-ID"]
    user = User.find_by(google_channel_id: channel_id)

    unless user
      head :ok and return
    end

    resource_state = request.headers["X-Goog-Resource-State"]

    if resource_state == "sync"
      handle_initial_sync(user)
    else
      handle_incremental_sync(user)
    end

    head :ok
  rescue StandardError => e
    Rails.logger.error "[Webhooks::GoogleCalendarController] Error: #{e.message}"
    head :ok
  end

  private

  def handle_initial_sync(user)
    ActsAsTenant.with_tenant(user.account) do
      service = GoogleCalendarService.new(user)
      service.incremental_sync
    end
  end

  def handle_incremental_sync(user)
    ActsAsTenant.with_tenant(user.account) do
      service = GoogleCalendarService.new(user)
      changed_events = service.incremental_sync

      changed_events.each do |event|
        process_event(user, event)
      end
    end
  end

  def process_event(user, event)
    booking = Booking.find_by(google_event_id: event.id)
    return unless booking

    if event.status == "cancelled"
      booking.cancel! unless booking.cancelled?
    else
      start_time = parse_event_time(event.start)
      end_time   = parse_event_time(event.end)

      if start_time && (booking.starts_at != start_time || booking.ends_at != end_time)
        booking.skip_google_sync = true
        booking.update!(starts_at: start_time, ends_at: end_time)
      end
    end
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error "[GoogleCalendarWebhook] Could not update booking #{booking&.id}: #{e.message}"
  end

  def parse_event_time(event_dt)
    return nil unless event_dt
    if event_dt.date_time
      event_dt.date_time
    elsif event_dt.date
      Time.zone.parse(event_dt.date.to_s)
    end
  end
end
