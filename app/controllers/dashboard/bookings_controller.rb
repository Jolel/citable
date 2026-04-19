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
      :address, :recurrence_rule_id
    )
  end

  def schedule_reminders(booking)
    [{ kind: "24h", offset: 24.hours }, { kind: "2h", offset: 2.hours }].each do |reminder|
      fire_at = booking.starts_at - reminder[:offset]
      next if fire_at <= Time.current

      ReminderSchedule.find_or_create_by!(account: current_account, booking: booking, kind: reminder[:kind]) do |r|
        r.scheduled_for = fire_at
      end
      ReminderJob.set(wait_until: fire_at).perform_later(booking.id, reminder[:kind])
    end
  end
end
