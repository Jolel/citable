class RenewGoogleWatchJob < ApplicationJob
  queue_as :default

  def perform
    User.where.not(google_channel_id: nil)
        .where("google_channel_expires_at <= ?", 1.day.from_now)
        .find_each do |user|
          ActsAsTenant.with_tenant(user.account) do
            webhook_url = Rails.application.routes.url_helpers.webhooks_google_calendar_url(
              host: Rails.application.config.action_mailer.default_url_options[:host]
            )
            GoogleCalendarService.new(user).setup_watch(webhook_url)
          rescue StandardError => e
            Rails.logger.error "[RenewGoogleWatchJob] Failed to renew watch for user #{user.id}: #{e.message}"
          end
        end
  end
end
