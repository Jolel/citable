# frozen_string_literal: true

class Dashboard::GoogleCalendarController < Dashboard::BaseController
  def disconnect
    current_user.disconnect_google!
    redirect_to dashboard_settings_path, notice: "Google Calendar desconectado."
  end
end
