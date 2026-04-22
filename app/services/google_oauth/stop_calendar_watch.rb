# frozen_string_literal: true

module GoogleOauth
  class StopCalendarWatch
    include Dry::Monads[:result]

    def self.call(...) = new.call(...)

    def call(user:, calendar: nil)
      return Success() unless user.google_channel_id.present?

      adapter = calendar || CalendarAdapter.new(user)
      adapter.stop_channel(user.google_channel_id)
      Success()
    rescue StandardError => e
      Rails.logger.warn "[GoogleOauth::StopCalendarWatch] Could not stop channel for user #{user.id}: #{e.message}"
      Success()
    end
  end
end
