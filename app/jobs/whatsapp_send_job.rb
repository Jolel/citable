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
    tz_time    = booking.starts_at.in_time_zone(booking.account.timezone)
    time_str   = localized_appointment_str(tz_time)

    case kind.to_sym
    when :confirmation
      "Hola #{booking.customer.name} 👋 Tu cita con #{owner_name} está confirmada para #{time_str}. Si necesitas cambiarla escríbenos aquí."
    when :"24h"
      "Hola #{booking.customer.name}! 😊 Te recordamos que mañana tienes cita con #{owner_name} a las #{tz_time.strftime("%H:%M")}. Si necesitas cancelar o mover tu cita, solo escríbenos."
    when :"2h"
      "Hola #{booking.customer.name}! Tu cita con #{owner_name} es en 2 horas (#{tz_time.strftime("%H:%M")}). ¡Nos vemos pronto!"
    end
  end

  def localized_appointment_str(time)
    day   = I18n.t("date.day_names",   locale: :"es-MX")[time.wday]
    month = I18n.t("date.month_names", locale: :"es-MX")[time.month]
    "el #{day} #{time.day} de #{month} a las #{time.strftime("%H:%M")}"
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
