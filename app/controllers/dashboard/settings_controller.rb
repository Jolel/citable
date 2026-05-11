# frozen_string_literal: true

class Dashboard::SettingsController < Dashboard::BaseController
  before_action :require_owner!

  DAY_KEYS = %w[mon tue wed thu fri sat sun].freeze

  def show
    @account = current_account
  end

  def update
    @account = current_account
    if @account.update(account_params)
      redirect_to dashboard_settings_path, notice: "Configuración guardada."
    else
      render :show, status: :unprocessable_entity
    end
  end

  private

  def account_params
    permitted = params.require(:account).permit(:name, :timezone, :address, business_hours: {})
    permitted[:business_hours] = normalize_business_hours(permitted[:business_hours]) if permitted.key?(:business_hours)
    permitted
  end

  # Form posts: account[business_hours][mon][open], [close], [closed].
  # We store as: { "mon" => ["09:00", "19:00"] } for open days, { "mon" => nil } for closed.
  def normalize_business_hours(raw)
    return {} if raw.blank?

    DAY_KEYS.each_with_object({}) do |day, out|
      entry = raw[day]
      if entry.is_a?(ActionController::Parameters) || entry.is_a?(Hash)
        if entry["closed"] == "1"
          out[day] = nil
        else
          open_t  = entry["open"].to_s.presence
          close_t = entry["close"].to_s.presence
          out[day] = (open_t && close_t) ? [ open_t, close_t ] : nil
        end
      else
        out[day] = nil
      end
    end
  end

  def require_owner!
    redirect_to dashboard_bookings_path, alert: "Acceso restringido." unless current_user.owner?
  end
end
