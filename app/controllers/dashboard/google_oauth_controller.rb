class Dashboard::GoogleOauthController < Dashboard::BaseController
  GOOGLE_AUTH_URI  = "https://accounts.google.com/o/oauth2/v2/auth"
  GOOGLE_TOKEN_URI = "https://oauth2.googleapis.com/token"
  USERINFO_URI     = "https://www.googleapis.com/oauth2/v2/userinfo"
  SCOPES = %w[https://www.googleapis.com/auth/calendar email].freeze

  def authorize
    state = SecureRandom.hex(24)
    session[:google_oauth_state] = state
    client = build_client
    redirect_to client.authorization_uri(
      scope: SCOPES, state: state, access_type: "offline",
      prompt: "consent", include_granted_scopes: "true"
    ).to_s, allow_other_host: true
  end

  def callback
    unless params[:state].present? && params[:state] == session.delete(:google_oauth_state)
      return redirect_to dashboard_settings_path, alert: "Estado OAuth inválido. Intenta de nuevo."
    end

    if params[:error].present?
      return redirect_to dashboard_settings_path, alert: "No se pudo conectar con Google: #{params[:error]}"
    end

    client = build_client
    client.code = params[:code]
    client.fetch_access_token!

    userinfo = fetch_userinfo(client.access_token)

    current_user.update!(
      google_oauth_token:      client.access_token,
      google_refresh_token:    client.refresh_token.presence || current_user.google_refresh_token,
      google_token_expires_at: Time.at(client.expires_at.to_i),
      google_calendar_id:      userinfo["email"]
    )

    redirect_to dashboard_settings_path, notice: "Google Calendar conectado correctamente."
  rescue Signet::AuthorizationError, Signet::RemoteServerError => e
    Rails.logger.error "[GoogleOauth] Token exchange failed: #{e.message}"
    redirect_to dashboard_settings_path, alert: "Error al conectar con Google. Intenta de nuevo."
  end

  private

  def build_client
    Signet::OAuth2::Client.new(
      client_id:            Rails.application.credentials.dig(:google, :client_id),
      client_secret:        Rails.application.credentials.dig(:google, :client_secret),
      authorization_uri:    GOOGLE_AUTH_URI,
      token_credential_uri: GOOGLE_TOKEN_URI,
      redirect_uri:         callback_dashboard_google_oauth_url
    )
  end

  def fetch_userinfo(access_token)
    uri = URI(USERINFO_URI)
    req = Net::HTTP::Get.new(uri)
    req["Authorization"] = "Bearer #{access_token}"
    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |h| h.request(req) }
    raise Signet::AuthorizationError, "Userinfo HTTP #{res.code}" unless res.is_a?(Net::HTTPSuccess)
    JSON.parse(res.body)
  end
end
