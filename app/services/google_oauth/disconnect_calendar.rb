# frozen_string_literal: true

module GoogleOauth
  class DisconnectCalendar
    include Dry::Monads[:result]

    def self.call(...) = new.call(...)

    def call(user:, calendar: nil)
      StopCalendarWatch.call(user: user, calendar: calendar)
        .bind { disconnect_user(user) }
    end

    private

    def disconnect_user(user)
      user.disconnect_google!
      Success(user)
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error "[GoogleOauth::DisconnectCalendar] #{e.message}"
      Failure(:disconnect_failed)
    end
  end
end
