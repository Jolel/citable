# frozen_string_literal: true

class Dashboard::StaffController < Dashboard::BaseController
  include Dashboard::OwnerOnly

  before_action :require_owner!
  before_action :set_staff_member, only: %i[show edit update destroy reset_password]

  def index
    @staff = current_account.users.order(:name)
  end

  def show
    @availabilities = @staff_member.staff_availabilities.order(:day_of_week)
  end

  def new
    @staff_member = User.new
  end

  # Owner bootstraps a new staff member with an initial password. Out-of-band
  # confirmation is enforced separately via Devise :confirmable for email changes.
  def create
    @staff_member = User.new(staff_create_params)
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

  # Update never accepts password fields. Email change goes through Devise
  # :confirmable (the new address must click a link in their inbox before
  # the change takes effect). Password rotation is driven by #reset_password
  # which dispatches a Devise password-reset email — i.e. out-of-band proof
  # that the staff member controls the mailbox.
  def update
    if @staff_member.update(staff_update_params)
      redirect_to dashboard_staff_path(@staff_member), notice: "Colaborador actualizado."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def reset_password
    @staff_member.send_reset_password_instructions
    redirect_to dashboard_staff_path(@staff_member),
                notice: "Enviamos un correo a #{@staff_member.email} para restablecer su contraseña."
  end

  def destroy
    @staff_member.destroy
    redirect_to dashboard_staff_index_path, notice: "Colaborador eliminado."
  end

  private

  def set_staff_member
    @staff_member = current_account.users.find(params[:id])
  end

  def staff_create_params
    params.require(:user).permit(:name, :email, :phone, :password, :password_confirmation)
  end

  def staff_update_params
    params.require(:user).permit(:name, :email, :phone)
  end
end
