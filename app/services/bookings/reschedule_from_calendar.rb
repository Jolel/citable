# frozen_string_literal: true

module Bookings
  class RescheduleFromCalendar
    include Dry::Monads[:result]

    def self.call(...) = new.call(...)

    def call(booking:, starts_at:, user:)
      booking.assign_attributes(
        starts_at: starts_at,
        ends_at: starts_at + original_duration(booking),
        user: user
      )

      warnings = CalendarPlacementWarnings.call(
        booking: booking,
        starts_at: booking.starts_at,
        ends_at: booking.ends_at,
        user: booking.user
      ).value!

      booking.save!

      Success(booking: booking, warnings: warnings)
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error "[Bookings::RescheduleFromCalendar] #{e.message}"
      Failure(:invalid_booking)
    rescue StandardError => e
      Rails.logger.error "[Bookings::RescheduleFromCalendar] #{e.message}"
      Failure(:reschedule_failed)
    end

    private

    def original_duration(booking)
      booking.ends_at - booking.starts_at
    end
  end
end
