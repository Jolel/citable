class Dashboard::CustomersController < Dashboard::BaseController
  before_action :set_customer, only: %i[show edit update destroy]

  def index
    @customers = Customer.by_name
    @customers = @customers.with_tag(params[:tag]) if params[:tag].present?
    @customers = @customers.where("name ILIKE ? OR phone LIKE ?", "%#{params[:q]}%", "%#{params[:q]}%") if params[:q].present?
  end

  def show
    @bookings = @customer.bookings.includes(:service, :user).order(starts_at: :desc)
  end

  def new
    @customer = Customer.new
  end

  def create
    @customer = Customer.new(customer_params)
    if @customer.save
      redirect_to dashboard_customer_path(@customer), notice: "Cliente creado exitosamente."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @customer.update(customer_params)
      redirect_to dashboard_customer_path(@customer), notice: "Cliente actualizado."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @customer.destroy
    redirect_to dashboard_customers_path, notice: "Cliente eliminado."
  end

  private

  def set_customer
    @customer = Customer.find(params[:id])
  end

  def customer_params
    params.require(:customer).permit(:name, :phone, :notes, tags: [], custom_fields: {})
  end
end
