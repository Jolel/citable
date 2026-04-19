class WhatsappSendJob < ApplicationJob
  queue_as :notifications

  def perform(booking_id, kind)
    booking = Booking.find_by(id: booking_id)
    return unless booking

    ActsAsTenant.with_tenant(booking.account) do
      # Atomically reserve a quota slot: single UPDATE with condition prevents
      # race conditions that would allow concurrent jobs to exceed the limit.
      quota_limit = booking.account.whatsapp_quota_limit
      reserved = Account.where(id: booking.account.id)
                        .where("whatsapp_quota_used < ?", quota_limit)
                        .update_all("whatsapp_quota_used = whatsapp_quota_used + 1")
      return if reserved == 0

      message_body = build_message(booking, kind)
      to_number    = "whatsapp:#{booking.customer.normalized_phone}"

      begin
        send_message(to: to_number, body: message_body, booking: booking)
      rescue
        # Roll back the quota slot if the send failed so it isn't wasted.
        booking.account.decrement!(:whatsapp_quota_used)
        raise
      end
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
    else
      raise ArgumentError, "unknown reminder kind: #{kind}"
    end
  end

  def twilio_client
    Twilio::REST::Client.new(
      Rails.application.credentials.dig!(:twilio, :account_sid),
      Rails.application.credentials.dig!(:twilio, :auth_token)
    )
  end

  def send_message(to:, body:, booking:)
    client = twilio_client
    from   = Rails.application.credentials.dig!(:twilio, :whatsapp_number)

    message = client.messages.create(
      from: "whatsapp:#{from}",
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
