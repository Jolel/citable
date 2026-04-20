# frozen_string_literal: true

class Dashboard::ServicesController < Dashboard::BaseController
  before_action :set_service, only: %i[show edit update destroy toggle_active]

  def index
    @services = current_account.services.order(:name)
  end

  def show
  end

  def new
    @service = current_account.services.build
  end

  def create
    @service = current_account.services.build(service_params)
    if @service.save
      redirect_to dashboard_services_path, notice: "Servicio creado exitosamente."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @service.update(service_params)
      redirect_to dashboard_services_path, notice: "Servicio actualizado."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @service.update!(active: false)
    redirect_to dashboard_services_path, notice: "Servicio desactivado."
  end

  def toggle_active
    @service.update!(active: !@service.active?)
    redirect_to dashboard_services_path
  end

  private

  def set_service
    @service = current_account.services.find(params[:id])
  end

  def service_params
    params.require(:service).permit(
      :name, :duration_minutes, :price_cents, :requires_address, :deposit_amount_cents, :active
    )
  end
end
