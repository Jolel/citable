# frozen_string_literal: true

class Dashboard::BookingsController < Dashboard::BaseController
  before_action :set_booking, only: %i[show edit update destroy confirm cancel mark_completed mark_no_show]
  before_action :set_form_collections, only: %i[new create edit update]

  def index
    @bookings = current_account.bookings.includes(:customer, :service, :user)
                               .order(:starts_at)
    @bookings = case params[:filter]
    when "upcoming" then @bookings.upcoming
    when "today"    then @bookings.today
    when "past"     then @bookings.past
    else                 @bookings.upcoming
    end
  end

  def show
  end

  def new
    @booking = current_account.bookings.build
  end

  def create
    @booking = current_account.bookings.build(booking_params.merge(scoped_associations))
    if @booking.save
      redirect_to dashboard_booking_path(@booking), notice: "Cita creada exitosamente."
    else
      render :new, status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordNotFound
    @booking = current_account.bookings.build
    flash.now[:alert] = "El servicio, cliente o colaborador seleccionado no es válido."
    render :new, status: :unprocessable_entity
  end

  def edit
  end

  def update
    if @booking.update(booking_params.merge(scoped_associations))
      redirect_to dashboard_booking_path(@booking), notice: "Cita actualizada."
    else
      render :edit, status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordNotFound
    flash.now[:alert] = "El servicio, cliente o colaborador seleccionado no es válido."
    render :edit, status: :unprocessable_entity
  end

  def destroy
    @booking.cancel!
    redirect_to dashboard_bookings_path, notice: "Cita cancelada."
  end

  def confirm
    @booking.confirm!
    redirect_to dashboard_booking_path(@booking), notice: "Cita confirmada."
  end

  def cancel
    @booking.cancel!
    redirect_to dashboard_bookings_path, notice: "Cita cancelada."
  end

  def mark_completed
    @booking.mark_completed!
    redirect_to dashboard_booking_path(@booking), notice: "Cita marcada como completada."
  end

  def mark_no_show
    @booking.mark_no_show!
    redirect_to dashboard_booking_path(@booking), notice: "Cita marcada como no show."
  end

  private

  def set_booking
    @booking = current_account.bookings.find(params[:id])
  end

  def set_form_collections
    @services = current_account.services.active
    @staff = current_account.users
    @customers = current_account.customers.by_name
  end

  def booking_params
    params.require(:booking).permit(:starts_at, :ends_at, :address)
  end

  # Re-resolve every FK against current_account collections so a tampered
  # form value cannot reference another tenant's record. Status is excluded
  # entirely; transitions go through dedicated member actions that fire the
  # correct side effects (Google Calendar sync, confirmed_at, etc.).
  def scoped_associations
    attrs = {}
    if (id = params.dig(:booking, :customer_id)).present?
      attrs[:customer] = current_account.customers.find(id)
    end
    if (id = params.dig(:booking, :service_id)).present?
      attrs[:service] = current_account.services.find(id)
    end
    if (id = params.dig(:booking, :user_id)).present?
      attrs[:user] = current_account.users.find(id)
    end
    if (id = params.dig(:booking, :recurrence_rule_id)).present?
      attrs[:recurrence_rule] = current_account.recurrence_rules.find(id)
    end
    attrs
  end
end
