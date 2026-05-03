# frozen_string_literal: true

class Public::BookingsController < ApplicationController
  before_action :set_account

  layout "public"

  rate_limit to: 5, within: 1.minute,
             by: -> { "public_booking_ip:#{request.remote_ip}:#{params[:account_whatsapp]}" },
             with: -> { render plain: "Demasiados intentos. Intenta más tarde.", status: :too_many_requests },
             only: :create

  rate_limit to: 3, within: 1.hour,
             by: -> { "public_booking_phone:#{Account.normalize_whatsapp_number(params[:customer_phone])}:#{params[:account_whatsapp]}" },
             with: -> { render plain: "Demasiados intentos. Intenta más tarde.", status: :too_many_requests },
             only: :create

  def new
    @booking  = @account.bookings.build
    @services = @account.services.active
  end

  def create
    service = @account.services.active.find_by(id: params.dig(:booking, :service_id))
    return render_invalid("Selecciona un servicio válido.") unless service

    customer = find_or_create_customer
    @booking = @account.bookings.build(
      booking_params.merge(
        customer: customer,
        service:  service,
        user:     PublicBookings::StaffPicker.call(account: @account, service: service)
      )
    )

    if @booking.save
      WhatsappSendJob.perform_later(@booking.id, :confirmation)
      redirect_to public_booking_confirmation_path(
        account_whatsapp: @account.whatsapp_number,
        token: @booking.confirmation_token
      )
    else
      @services = @account.services.active
      render :new, status: :unprocessable_entity
    end
  end

  def confirmation
    @booking = @account.bookings.find_by!(confirmation_token: params[:token])
  end

  private

  def set_account
    normalized = Account.normalize_whatsapp_number(params[:account_whatsapp])
    @account = Account.find_by(whatsapp_number: normalized) if normalized
    render plain: "Negocio no encontrado", status: :not_found unless @account
  end

  def find_or_create_customer
    @account.customers.find_or_create_by!(phone: params[:customer_phone]) do |c|
      c.name = params[:customer_name]
    end
  end

  def booking_params
    params.require(:booking).permit(:starts_at, :address)
  end

  def render_invalid(message)
    @services = @account.services.active
    @booking  = @account.bookings.build
    flash.now[:alert] = message
    render :new, status: :unprocessable_entity
  end
end
