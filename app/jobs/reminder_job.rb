# frozen_string_literal: true

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
    # TODO: integrate Resend for email fallback
    Rails.logger.info "[ReminderJob] Email fallback for booking #{booking.id}, kind=#{kind}"
  end
end
