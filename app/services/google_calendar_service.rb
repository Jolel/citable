class GoogleCalendarService
  CALENDAR_SUMMARY = "Citable"

  def initialize(user)
    @user = user
    @service = Google::Apis::CalendarV3::CalendarService.new
    @service.authorization = build_authorization
    refresh_token! if @user.google_token_expired?
  end

  # Returns the "Citable" calendar ID, creating it if it doesn't exist.
  def ensure_calendar
    if @user.google_calendar_id.present?
      verify_calendar_exists
    else
      create_citable_calendar
    end
    @user.google_calendar_id
  end

  # Pushes a booking to Google Calendar.
  # action: :create, :update, or :cancel
  def sync_booking(booking, action)
    calendar_id = ensure_calendar

    with_token_refresh do
      case action.to_sym
      when :create
        event = build_event(booking)
        result = @service.insert_event(calendar_id, event)
        booking.update_column(:google_event_id, result.id)
      when :update
        return unless booking.google_event_id.present?
        event = build_event(booking)
        @service.patch_event(calendar_id, booking.google_event_id, event)
      when :cancel
        return unless booking.google_event_id.present?
        patch = Google::Apis::CalendarV3::Event.new(
          summary: "❌ [Cancelada] #{event_title(booking)}"
        )
        @service.patch_event(calendar_id, booking.google_event_id, patch)
      end
    end
  end

  # Registers a push notification channel for this user's calendar.
  def setup_watch(webhook_url)
    calendar_id = ensure_calendar

    with_token_refresh do
      channel = Google::Apis::CalendarV3::Channel.new(
        id:      SecureRandom.uuid,
        type:    "web_hook",
        address: webhook_url,
        token:   Rails.application.credentials.google&.webhook_token
      )
      result = @service.watch_event(calendar_id, channel)
      expiry = result.expiration ? Time.at(result.expiration.to_i / 1000).utc : 7.days.from_now

      @user.update!(
        google_channel_id:         result.id,
        google_channel_expires_at: expiry
      )
    end
  end

  # Performs an incremental sync using the stored sync token.
  # Returns the list of changed events.
  def incremental_sync
    calendar_id = @user.google_calendar_id
    return [] unless calendar_id.present?

    with_token_refresh do
      options = { single_events: true }
      options[:sync_token] = @user.google_sync_token if @user.google_sync_token.present?

      result = @service.list_events(calendar_id, **options)
      @user.update_column(:google_sync_token, result.next_sync_token) if result.next_sync_token
      result.items || []
    rescue Google::Apis::GoneError
      # Sync token expired — fall back to full re-sync
      @user.update_column(:google_sync_token, nil)
      full_sync_and_get_token
      []
    end
  end

  def refresh_token!
    auth = build_authorization
    auth.refresh!
    @user.update!(
      google_oauth_token:      auth.access_token,
      google_token_expires_at: auth.expires_at
    )
    @service.authorization = auth
  end

  private

  def build_authorization
    Signet::OAuth2::Client.new(
      client_id:        Rails.application.credentials.google&.client_id,
      client_secret:    Rails.application.credentials.google&.client_secret,
      token_credential_uri: "https://oauth2.googleapis.com/token",
      access_token:     @user.google_oauth_token,
      refresh_token:    @user.google_refresh_token,
      expires_at:       @user.google_token_expires_at
    )
  end

  def with_token_refresh
    yield
  rescue Google::Apis::AuthorizationError
    refresh_token!
    yield
  rescue Signet::AuthorizationError
    # Refresh token revoked — clear all google data
    Rails.logger.warn "[GoogleCalendarService] Refresh token revoked for user #{@user.id}. Clearing google data."
    @user.update_columns(
      google_oauth_token:      nil,
      google_refresh_token:    nil,
      google_calendar_id:      nil,
      google_token_expires_at: nil,
      google_channel_id:       nil,
      google_channel_expires_at: nil,
      google_sync_token:       nil
    )
    nil
  end

  def verify_calendar_exists
    @service.get_calendar(@user.google_calendar_id)
  rescue Google::Apis::ClientError
    # Calendar was deleted from Google side — recreate it
    create_citable_calendar
  end

  def create_citable_calendar
    calendar = Google::Apis::CalendarV3::Calendar.new(summary: CALENDAR_SUMMARY)
    result   = @service.insert_calendar(calendar)
    @user.update_column(:google_calendar_id, result.id)
  end

  def full_sync_and_get_token
    result = @service.list_events(@user.google_calendar_id, single_events: true)
    @user.update_column(:google_sync_token, result.next_sync_token) if result.next_sync_token
  end

  def build_event(booking)
    timezone = booking.account.timezone.presence || "America/Mexico_City"

    Google::Apis::CalendarV3::Event.new(
      summary:     event_title(booking),
      description: event_description(booking),
      location:    booking.address.presence,
      start:       Google::Apis::CalendarV3::EventDateTime.new(
        date_time: booking.starts_at.iso8601,
        time_zone: timezone
      ),
      end:         Google::Apis::CalendarV3::EventDateTime.new(
        date_time: booking.ends_at.iso8601,
        time_zone: timezone
      )
    )
  end

  def event_title(booking)
    service_name  = booking.service&.name  || "Servicio"
    customer_name = booking.customer&.name || "Cliente"
    "#{service_name} – #{customer_name}"
  end

  def event_description(booking)
    parts = []
    parts << "Cliente: #{booking.customer&.phone}" if booking.customer&.phone.present?
    parts << "Notas: #{booking.notes}"             if booking.respond_to?(:notes) && booking.notes.present?
    parts << "Citable ID: #{booking.id}"
    parts.join("\n")
  end
end
