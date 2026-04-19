class Public::BookingsController < ApplicationController
  before_action :require_account!

  layout "public"

  def new
    @booking = Booking.new
    @services = Service.active
  end

  def create
    customer = find_or_create_customer
    @booking = Booking.new(booking_params.merge(customer: customer))

    if @booking.save
      WhatsappSendJob.perform_later(@booking.id, :confirmation)
      GoogleCalendarSyncJob.perform_later(@booking.id)
      schedule_reminders(@booking)
      redirect_to public_booking_confirmation_path(@booking)
    else
      @services = Service.active
      render :new, status: :unprocessable_entity
    end
  end

  def confirmation
    @booking = Booking.find(params[:id])
  end

  private

  def require_account!
    unless current_tenant
      render plain: "Negocio no encontrado", status: :not_found
    end
  end

  def find_or_create_customer
    raw_phone = params[:customer_phone].to_s.strip
    raise ActionController::BadRequest, "Teléfono requerido" if raw_phone.blank?

    Customer.find_or_create_by!(phone: raw_phone) do |c|
      c.name = params[:customer_name].to_s.strip
    end
  end

  def schedule_reminders(booking)
    [{ kind: "24h", offset: 24.hours }, { kind: "2h", offset: 2.hours }].each do |reminder|
      fire_at = booking.starts_at - reminder[:offset]
      next if fire_at <= Time.current

      ReminderSchedule.find_or_create_by!(account: current_tenant, booking: booking, kind: reminder[:kind]) do |r|
        r.scheduled_for = fire_at
      end
      ReminderJob.set(wait_until: fire_at).perform_later(booking.id, reminder[:kind])
    end
  end

  def booking_params
    params.require(:booking).permit(:service_id, :user_id, :starts_at, :address)
  end
end
