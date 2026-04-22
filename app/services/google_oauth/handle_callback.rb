# frozen_string_literal: true

module GoogleOauth
  class HandleCallback
    include Dry::Monads[:result]

    def self.call(...) = new.call(...)

    def call(state:, code:, redirect_uri:, account:, current_user:, webhook_url: nil)
      VerifyStateToken.call(state)
        .bind { |state_data| authorize(state_data, account, current_user) }
        .bind { |user, state_data| connect(user, code, redirect_uri, webhook_url, state_data[:return_to]) }
    end

    private

    def authorize(state_data, account, current_user)
      user = account.users.find_by(id: state_data[:user_id])
      return Failure(:user_not_found) unless user

      policy = CalendarAccessPolicy.new(current_user: current_user, target_user: user)
      return Failure(policy.error) unless policy.allowed?

      Success([ user, state_data ])
    end

    def connect(user, code, redirect_uri, webhook_url, return_to)
      ConnectCalendar.call(user: user, code: code, redirect_uri: redirect_uri, webhook_url: webhook_url)
        .fmap { { user: user, return_to: return_to } }
    end
  end
end
