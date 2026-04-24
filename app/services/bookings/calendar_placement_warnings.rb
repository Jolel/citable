# frozen_string_literal: true

module Bookings
  class CalendarPlacementWarnings
    include Dry::Monads[:result]

    def self.call(...) = new.call(...)

    def call(booking:, starts_at:, ends_at:, user:)
      warnings = []
      warnings << :outside_availability if outside_availability?(starts_at:, ends_at:, user:)
      warnings << :overlap if overlap?(booking:, starts_at:, ends_at:, user:)
      Success(warnings)
    end

    private

    def outside_availability?(starts_at:, ends_at:, user:)
      availability = user.staff_availabilities.active.for_day(starts_at.wday).first
      return true unless availability

      day_start = starts_at.in_time_zone.beginning_of_day
      starts_seconds = (starts_at - day_start).to_i
      ends_seconds = (ends_at - day_start).to_i

      starts_seconds < seconds_since_midnight(availability.start_time) ||
        ends_seconds > seconds_since_midnight(availability.end_time)
    end

    def overlap?(booking:, starts_at:, ends_at:, user:)
      booking.account.bookings.active
             .where(user: user)
             .where.not(id: booking.id)
             .where("starts_at < ? AND ends_at > ?", ends_at, starts_at)
             .exists?
    end

    def seconds_since_midnight(value)
      (value.hour * 3600) + (value.min * 60) + value.sec
    end
  end
end
