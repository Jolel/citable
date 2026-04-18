class Dashboard::SettingsController < Dashboard::BaseController
  before_action :require_owner!

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
    params.require(:account).permit(:name, :timezone, :subdomain)
  end

  def require_owner!
    redirect_to dashboard_bookings_path, alert: "Acceso restringido." unless current_user.owner?
  end
end
