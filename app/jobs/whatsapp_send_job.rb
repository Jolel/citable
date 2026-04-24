# frozen_string_literal: true

class WhatsappSendJob < ApplicationJob
  include Dry::Monads[:result]

  queue_as :notifications

  FROM = Rails.application.credentials.dig(:twilio, :whatsapp_number)

  def perform(booking_id, kind)
    booking = Booking.find_by(id: booking_id)
    return unless booking
    return if booking.account.whatsapp_quota_exceeded?

    body = build_message(booking, kind)
    to   = booking.customer.phone

    result = send_whatsapp.call(to: to, from: FROM, body: body)

    case result
    in Success[sent]
      log_message(booking, body, "sent", sent.sid)
      booking.account.increment!(:whatsapp_quota_used)
    in Failure[error]
      log_message(booking, body, "failed")
      Rails.logger.error "[WhatsappSendJob] Twilio error for booking #{booking.id}: #{error.message}"
      raise error
    end
  end

  private

  def send_whatsapp
    Citable::Container["core.use_cases.send_whatsapp_message"]
  end

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

  def log_message(booking, body, status, external_id = nil)
    MessageLog.create!(
      account:     booking.account,
      booking:     booking,
      customer:    booking.customer,
      channel:     "whatsapp",
      direction:   "outbound",
      body:        body,
      status:      status,
      external_id: external_id
    )
  end
end
