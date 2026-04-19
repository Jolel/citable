class Users::OmniauthCallbacksController < Devise::OmniauthCallbacksController
  def google_oauth2
    unless current_user
      redirect_to new_user_session_path, alert: "Debes iniciar sesión primero."
      return
    end

    auth = request.env["omniauth.auth"]
    current_user.update!(
      google_oauth_token:      auth.credentials.token,
      google_refresh_token:    auth.credentials.refresh_token.presence || current_user.google_refresh_token,
      google_token_expires_at: Time.at(auth.credentials.expires_at),
      google_calendar_id:      auth.extra.raw_info.email
    )

    origin = request.env["omniauth.origin"].presence
    redirect_to(origin || dashboard_settings_path, notice: "Google Calendar conectado correctamente.")
  end

  def failure
    redirect_to dashboard_settings_path, alert: "No se pudo conectar con Google: #{failure_message}"
  end
end
