# frozen_string_literal: true

module GoogleOauth
  class HandleCallback
    include Dry::Monads[:result]

    def self.call(...) = new.call(...)

    def call(state:, code:, redirect_uri:, account:, current_user:, session_nonce:, webhook_url: nil)
      VerifyStateToken.call(state)
        .bind { |state_data| authorize(state_data, account, current_user, session_nonce) }
        .bind { |user, state_data| connect(user, code, redirect_uri, webhook_url, state_data[:return_to]) }
    end

    private

    # Reject the callback unless the signed state token's initiator_id and
    # nonce both match the current session. This blocks the audit's confused
    # deputy: an attacker minting a state token bound to their own user_id
    # and tricking the owner into completing the consent flow.
    def authorize(state_data, account, current_user, session_nonce)
      if state_data[:initiator_id] != current_user.id
        return Failure(:state_initiator_mismatch)
      end

      stored_nonce = session_nonce.to_s
      provided_nonce = state_data[:nonce].to_s
      if stored_nonce.blank? || !ActiveSupport::SecurityUtils.secure_compare(provided_nonce, stored_nonce)
        return Failure(:state_nonce_mismatch)
      end

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
