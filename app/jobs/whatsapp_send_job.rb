# frozen_string_literal: true

class WhatsappSendJob < ApplicationJob
  include Dry::Monads[:result]

  queue_as :notifications

  def perform(booking_id, kind)
    booking = Booking.find_by(id: booking_id)
    return unless booking
    return if booking.account.whatsapp_quota_exceeded?

    message_body = build_message(booking, kind)
    send_message(to: booking.customer.phone, body: message_body, booking: booking)
  end

  private

  def build_message(booking, kind)
    owner_name = booking.account.name
    time_str   = booking.starts_at.in_time_zone(booking.account.timezone)
                        .strftime("%A %d de %B a las %H:%M")

    case kind.to_sym
    when :confirmation
      "Hola #{booking.customer.name} 👋 Tu cita con #{owner_name} está confirmada para el #{time_str}. Si necesitas cambiarla escríbenos aquí."
    when :"24h"
      "Hola #{booking.customer.name}! Tu cita con #{owner_name} es mañana #{time_str}. Responde *1* para confirmar o *2* para cancelar."
    when :"2h"
      "Hola #{booking.customer.name}! Tu cita con #{owner_name} es en 2 horas (#{time_str}). ¡Nos vemos pronto!"
    end
  end

  def send_message(to:, body:, booking:)
    result = Whatsapp::MessageSender.call(
      account: booking.account,
      booking: booking,
      customer: booking.customer,
      to: to,
      body: body
    )

    case result
    in Success
      nil
    in Failure[ :quota_exceeded ]
      Rails.logger.warn "[WhatsappSendJob] Quota exceeded for account #{booking.account.id}, skipping booking #{booking.id}"
    in Failure
      raise "WhatsApp delivery failed for booking #{booking.id}"
    end
  end
end
