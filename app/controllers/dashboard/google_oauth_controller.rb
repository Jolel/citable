# frozen_string_literal: true

class Dashboard::GoogleOauthController < Dashboard::BaseController
  SCOPES = %w[
    https://www.googleapis.com/auth/calendar
    https://www.googleapis.com/auth/calendar.events
  ].freeze

  # GET /dashboard/google_oauth/connect(?user_id=X)
  def connect
    target_user = resolve_target_user
    return unless target_user

    state_payload = Base64.strict_encode64(
      JSON.generate(
        user_id:   target_user.id,
        return_to: extract_path(request.referer) || dashboard_staff_path(target_user)
      )
    )
    state_signed = "#{state_payload}.#{sign_state(state_payload)}"

    auth_client = build_auth_client
    auth_client.state = state_signed
    auth_client.update!(
      scope:                 SCOPES,
      access_type:           "offline",
      include_granted_scopes: "true",
      prompt:                "consent"
    )

    redirect_to auth_client.authorization_uri.to_s, allow_other_host: true
  end

  # GET /dashboard/google_oauth/callback
  def callback
    state_signed = params[:state].to_s
    payload_b64, _, signature = state_signed.rpartition(".")

    unless ActiveSupport::SecurityUtils.secure_compare(signature.to_s, sign_state(payload_b64))
      redirect_to dashboard_root_path, alert: "Estado OAuth inválido. Inténtalo de nuevo."
      return
    end

    state = JSON.parse(Base64.strict_decode64(payload_b64))
    target_user = current_account.users.find_by(id: state["user_id"])

    unless target_user
      redirect_to dashboard_root_path, alert: "Usuario no encontrado."
      return
    end

    unless current_user.owner? || current_user == target_user
      redirect_to dashboard_root_path, alert: "Acceso restringido."
      return
    end

    auth_client = build_auth_client
    auth_client.code = params[:code]
    auth_client.fetch_access_token!

    target_user.update!(
      google_oauth_token:      auth_client.access_token,
      google_refresh_token:    auth_client.refresh_token,
      google_token_expires_at: auth_client.expires_at
    )

    service = GoogleCalendarService.new(target_user)
    service.ensure_calendar

    if Rails.env.production?
      webhook_url = webhooks_google_calendar_url(
        host: request.host_with_port,
        protocol: request.protocol
      )
      service.setup_watch(webhook_url)
    end

    return_to = extract_path(state["return_to"]) || dashboard_staff_path(target_user)
    redirect_to return_to, notice: "Google Calendar conectado correctamente."
  rescue Signet::AuthorizationError, Google::Apis::AuthorizationError => e
    Rails.logger.error "[GoogleOauthController#callback] #{e.message}"
    redirect_to dashboard_root_path, alert: "No se pudo conectar con Google. Inténtalo de nuevo."
  end

  # DELETE /dashboard/google_oauth/disconnect(?user_id=X)
  def disconnect
    target_user = resolve_target_user
    return unless target_user

    if target_user.google_channel_id.present?
      begin
        service = GoogleCalendarService.new(target_user)
        channel = Google::Apis::CalendarV3::Channel.new(
          id:          target_user.google_channel_id,
          resource_id: nil
        )
        service.stop_channel(channel)
      rescue StandardError => e
        Rails.logger.warn "[GoogleOauthController#disconnect] Could not stop channel: #{e.message}"
      end
    end

    target_user.update_columns(
      google_oauth_token:        nil,
      google_refresh_token:      nil,
      google_calendar_id:        nil,
      google_token_expires_at:   nil,
      google_channel_id:         nil,
      google_channel_expires_at: nil,
      google_sync_token:         nil
    )

    return_to = request.referer || dashboard_staff_path(target_user)
    redirect_to return_to, notice: "Google Calendar desconectado."
  end

  private

  def resolve_target_user
    if params[:user_id].present?
      unless current_user.owner?
        redirect_to dashboard_root_path, alert: "Acceso restringido."
        return nil
      end
      user = current_account.users.find_by(id: params[:user_id])
      unless user
        redirect_to dashboard_root_path, alert: "Usuario no encontrado."
        return nil
      end
      user
    else
      current_user
    end
  end

  def build_auth_client
    Signet::OAuth2::Client.new(
      client_id:            Rails.application.credentials.dig(:google, :client_id),
      client_secret:        Rails.application.credentials.dig(:google, :client_secret),
      authorization_uri:    "https://accounts.google.com/o/oauth2/auth",
      token_credential_uri: "https://oauth2.googleapis.com/token",
      redirect_uri:         Rails.application.credentials.dig(:google, :redirect_uri) ||
                            callback_dashboard_google_oauth_url
    )
  end

  def sign_state(payload)
    OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, payload)
  end

  def extract_path(url)
    return nil if url.blank?
    URI.parse(url).path.presence
  rescue URI::InvalidURIError
    nil
  end
end
