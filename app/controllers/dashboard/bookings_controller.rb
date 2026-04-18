class Dashboard::BookingsController < Dashboard::BaseController
  before_action :set_booking, only: %i[show edit update destroy confirm cancel]

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
    @services = Service.active
    @staff = current_account.users
    @customers = Customer.by_name
  end

  def create
    @booking = Booking.new(booking_params)
    if @booking.save
      schedule_reminders(@booking)
      redirect_to dashboard_booking_path(@booking), notice: "Cita creada exitosamente."
    else
      @services = Service.active
      @staff = current_account.users
      @customers = Customer.by_name
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @services = Service.active
    @staff = current_account.users
    @customers = Customer.by_name
  end

  def update
    if @booking.update(booking_params)
      redirect_to dashboard_booking_path(@booking), notice: "Cita actualizada."
    else
      @services = Service.active
      @staff = current_account.users
      @customers = Customer.by_name
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

  def booking_params
    params.require(:booking).permit(
      :customer_id, :service_id, :user_id, :starts_at,
      :address, :recurrence_rule_id, :status
    )
  end

  def schedule_reminders(booking)
    ReminderSchedule.find_or_create_by!(account: current_account, booking: booking, kind: "24h") do |r|
      r.scheduled_for = booking.starts_at - 24.hours
    end
    ReminderSchedule.find_or_create_by!(account: current_account, booking: booking, kind: "2h") do |r|
      r.scheduled_for = booking.starts_at - 2.hours
    end
    ReminderJob.set(wait_until: booking.starts_at - 24.hours).perform_later(booking.id, "24h")
    ReminderJob.set(wait_until: booking.starts_at - 2.hours).perform_later(booking.id, "2h")
  end
end
