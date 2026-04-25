# frozen_string_literal: true

class Public::BookingsController < ApplicationController
  before_action :set_account

  layout "public"

  def new
    @booking = @account.bookings.build
    @services = @account.services.active
  end

  def create
    customer = find_or_create_customer
    @booking = @account.bookings.build(booking_params.merge(customer: customer))

    if @booking.save
      WhatsappSendJob.perform_later(@booking.id, :confirmation)
      redirect_to public_booking_confirmation_path(id: @booking)
    else
      @services = @account.services.active
      render :new, status: :unprocessable_entity
    end
  end

  def confirmation
    @booking = @account.bookings.find(params[:id])
  end

  private

  def set_account
    @account = Account.order(:id).first
    render plain: "Negocio no encontrado", status: :not_found unless @account
  end

  def find_or_create_customer
    @account.customers.find_or_create_by!(phone: params[:customer_phone]) do |c|
      c.name = params[:customer_name]
    end
  end

  def booking_params
    params.require(:booking).permit(:service_id, :user_id, :starts_at, :address)
  end
end
