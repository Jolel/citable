class Dashboard::ServicesController < Dashboard::BaseController
  before_action :set_service, only: %i[show edit update destroy toggle_active]

  def index
    @services = Service.order(:name)
  end

  def show
  end

  def new
    @service = Service.new
  end

  def create
    if current_account.free? && Service.count >= 3
      redirect_to dashboard_services_path, alert: "El plan Libre permite hasta 3 servicios. Actualiza a Pro para agregar más."
      return
    end

    @service = Service.new(service_params)
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
    @service = Service.find(params[:id])
  end

  def service_params
    params.require(:service).permit(
      :name, :duration_minutes, :price_cents, :requires_address, :deposit_amount_cents, :active
    )
  end
end
