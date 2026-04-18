class WhatsappSendJob < ApplicationJob
  queue_as :notifications

  TWILIO_ACCOUNT_SID = Rails.application.credentials.dig(:twilio, :account_sid)
  TWILIO_AUTH_TOKEN  = Rails.application.credentials.dig(:twilio, :auth_token)
  TWILIO_FROM        = Rails.application.credentials.dig(:twilio, :whatsapp_number)

  def perform(booking_id, kind)
    booking = Booking.find_by(id: booking_id)
    return unless booking

    ActsAsTenant.with_tenant(booking.account) do
      return if booking.account.whatsapp_quota_exceeded?

      message_body = build_message(booking, kind)
      to_number    = "whatsapp:#{booking.customer.phone}"

      send_message(to: to_number, body: message_body, booking: booking)

      booking.account.increment!(:whatsapp_quota_used)
    end
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
    client = Twilio::REST::Client.new(TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN)

    message = client.messages.create(
      from: "whatsapp:#{TWILIO_FROM}",
      to: to,
      body: body
    )

    MessageLog.create!(
      account: booking.account,
      booking: booking,
      customer: booking.customer,
      channel: "whatsapp",
      direction: "outbound",
      body: body,
      status: "sent",
      external_id: message.sid
    )
  rescue Twilio::REST::TwilioError => e
    Rails.logger.error "[WhatsappSendJob] Twilio error for booking #{booking.id}: #{e.message}"
    MessageLog.create!(
      account: booking.account,
      booking: booking,
      customer: booking.customer,
      channel: "whatsapp",
      direction: "outbound",
      body: body,
      status: "failed"
    )
    raise
  end
end
