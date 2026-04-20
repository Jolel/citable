# frozen_string_literal: true

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
    Customer.find_or_create_by!(phone: params[:customer_phone]) do |c|
      c.name = params[:customer_name]
    end
  end

  def booking_params
    params.require(:booking).permit(:service_id, :user_id, :starts_at, :address)
  end
end
