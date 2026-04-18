class Dashboard::StaffController < Dashboard::BaseController
  before_action :require_owner!
  before_action :set_staff_member, only: %i[show edit update destroy]

  def index
    @staff = current_account.users.order(:name)
  end

  def show
    @availabilities = @staff_member.staff_availabilities.order(:day_of_week)
  end

  def new
    @staff_member = User.new
  end

  def create
    @staff_member = User.new(staff_params)
    @staff_member.account = current_account
    @staff_member.role = :staff
    if @staff_member.save
      redirect_to dashboard_staff_index_path, notice: "Colaborador agregado."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @staff_member.update(staff_params.except(:password, :password_confirmation).reject { |_, v| v.blank? }.merge(staff_params.slice(:password, :password_confirmation).reject { |_, v| v.blank? }))
      redirect_to dashboard_staff_path(@staff_member), notice: "Colaborador actualizado."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @staff_member.destroy
    redirect_to dashboard_staff_index_path, notice: "Colaborador eliminado."
  end

  private

  def set_staff_member
    @staff_member = current_account.users.find(params[:id])
  end

  def staff_params
    params.require(:user).permit(:name, :email, :phone, :password, :password_confirmation)
  end

  def require_owner!
    redirect_to dashboard_bookings_path, alert: "Acceso restringido." unless current_user.owner?
  end
end
