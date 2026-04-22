# frozen_string_literal: true

module GoogleOauth
  class CalendarAdapter
    def initialize(user)
      @service = GoogleCalendarService.new(user)
    end

    def ensure_calendar
      @service.ensure_calendar
    end

    def setup_watch(webhook_url)
      @service.setup_watch(webhook_url)
    end

    def stop_channel(channel_id)
      channel = Google::Apis::CalendarV3::Channel.new(id: channel_id)
      @service.stop_channel(channel)
    end
  end
end
