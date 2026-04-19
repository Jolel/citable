class ReminderJob < ApplicationJob
  queue_as :reminders

  def perform(booking_id, kind)
    booking = Booking.find_by(id: booking_id)
    return unless booking
    return if booking.cancelled?

    ActsAsTenant.with_tenant(booking.account) do
      schedule = booking.reminder_schedules.find_by(kind: kind)
      return if schedule&.sent?

      if booking.account.whatsapp_quota_exceeded?
        send_email_reminder(booking, kind)
      else
        send_whatsapp_reminder(booking, kind)
      end

      schedule&.mark_sent!
    end
  end

  private

  def send_whatsapp_reminder(booking, kind)
    WhatsappSendJob.perform_now(booking.id, kind.to_sym)
  end

  def send_email_reminder(booking, kind)
    owner = booking.account.users.owners.first
    return unless owner

    subject = case kind.to_s
    when "24h" then "Recordatorio de cita para mañana — #{booking.customer.name}"
    when "2h"  then "Recordatorio de cita en 2 horas — #{booking.customer.name}"
    else            "Recordatorio de cita — #{booking.customer.name}"
    end

    time_str = booking.starts_at
                      .in_time_zone(booking.account.timezone)
                      .strftime("%A %d de %B a las %H:%M")

    html_body = <<~HTML
      <p>Hola #{owner.display_name} 👋</p>
      <p>No pudimos enviar el recordatorio de WhatsApp a <strong>#{booking.customer.name}</strong>
      (#{booking.customer.phone}) porque alcanzaste tu límite mensual de mensajes.</p>
      <p>Su cita es el <strong>#{time_str}</strong>.</p>
      <p>Te recomendamos contactarle directamente para confirmar.</p>
      <p>— El equipo de Citable</p>
    HTML

    result = Resend::Emails.send(
      from:    "Citable <no-reply@citable.mx>",
      to:      owner.email,
      subject: subject,
      html:    html_body
    )

    MessageLog.create!(
      account:   booking.account,
      booking:   booking,
      customer:  booking.customer,
      channel:   "email",
      direction: "outbound",
      body:      subject,
      status:    result[:id].present? ? "sent" : "failed"
    )

    Rails.logger.info "[ReminderJob] Email fallback sent to #{owner.email} for booking #{booking.id}"
  rescue => e
    Rails.logger.error "[ReminderJob] Email fallback failed for booking #{booking.id}: #{e.message}"
    MessageLog.create!(
      account:   booking.account,
      booking:   booking,
      customer:  booking.customer,
      channel:   "email",
      direction: "outbound",
      body:      subject || "email reminder",
      status:    "failed"
    )
  end
end
