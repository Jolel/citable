# frozen_string_literal: true

class Dashboard::BookingsController < Dashboard::BaseController
  before_action :set_booking, only: %i[show edit update destroy confirm cancel]
  before_action :set_form_collections, only: %i[new create edit update]

  def index
    @bookings = Booking.includes(:customer, :service, :user)
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
    @booking = Booking.new
  end

  def create
    @booking = Booking.new(booking_params)
    if @booking.save
      redirect_to dashboard_booking_path(@booking), notice: "Cita creada exitosamente."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @booking.update(booking_params)
      redirect_to dashboard_booking_path(@booking), notice: "Cita actualizada."
    else
      render :edit, status: :unprocessable_entity
    end
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

  private

  def set_booking
    @booking = Booking.find(params[:id])
  end

  def set_form_collections
    @services = Service.active
    @staff = current_account.users
    @customers = Customer.by_name
  end

  def booking_params
    params.require(:booking).permit(
      :customer_id, :service_id, :user_id, :starts_at,
      :address, :recurrence_rule_id, :status
    )
  end
end
