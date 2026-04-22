# frozen_string_literal: true

module GoogleOauth
  class ConnectCalendar
    include Dry::Monads[:result]

    def self.call(...) = new.call(...)

    def call(user:, code:, redirect_uri:, webhook_url: nil, oauth: nil)
      oauth ||= OauthAdapter.new(redirect_uri: redirect_uri)

      ExchangeOauthCode.call(code: code, oauth: oauth)
        .bind { |token| PersistOauthToken.call(user: user, token: token) }
        .bind { |updated_user| setup_calendar(updated_user, webhook_url) }
    end

    private

    def setup_calendar(user, webhook_url)
      calendar = CalendarAdapter.new(user)
      calendar.ensure_calendar
      calendar.setup_watch(webhook_url) if webhook_url.present?
      Success(user)
    rescue StandardError => e
      Rails.logger.error "[GoogleOauth::ConnectCalendar] Calendar setup failed: #{e.message}"
      Failure(:calendar_setup_failed)
    end
  end
end
