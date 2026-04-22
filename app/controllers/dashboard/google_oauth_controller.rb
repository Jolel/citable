# frozen_string_literal: true

class Dashboard::GoogleOauthController < Dashboard::BaseController
  include Dry::Monads[:result]

  before_action :set_target_user, only: %i[connect disconnect]

  # GET /dashboard/google_oauth/connect(?user_id=X)
  def connect
    result = GoogleOauth::BuildAuthorizationUrl.call(
      user_id:      @target_user.id,
      redirect_uri: callback_dashboard_google_oauth_url,
      return_to:    extract_path(request.referer)
    )

    case result
    in Success[auth_uri]
      redirect_to auth_uri, allow_other_host: true
    in Failure[reason]
      redirect_to dashboard_root_path, alert: t(".#{reason}")
    end
  end

  # GET /dashboard/google_oauth/callback
  def callback
    result = GoogleOauth::HandleCallback.call(
      state:        params[:state],
      code:         params[:code],
      redirect_uri: callback_dashboard_google_oauth_url,
      webhook_url:  production_webhook_url,
      account:      current_account,
      current_user: current_user
    )

    case result
    in Success[{ user:, return_to: }]
      redirect_to extract_path(return_to) || dashboard_staff_path(user), notice: t(".connected")
    in Failure[:invalid_state]
      redirect_to dashboard_root_path, alert: t(".invalid_state")
    in Failure[:user_not_found]
      redirect_to dashboard_root_path, alert: t(".user_not_found")
    in Failure[:access_denied]
      redirect_to dashboard_root_path, alert: t(".access_denied")
    in Failure[reason]
      Rails.logger.error "[GoogleOauthController#callback] #{reason}"
      redirect_to dashboard_root_path, alert: t(".connection_failed")
    end
  end

  # DELETE /dashboard/google_oauth/disconnect(?user_id=X)
  def disconnect
    result = GoogleOauth::DisconnectCalendar.call(user: @target_user)

    case result
    in Success
      redirect_to extract_path(request.referer) || dashboard_staff_path(@target_user),
                  notice: t(".disconnected")
    in Failure
      redirect_to dashboard_root_path, alert: t(".disconnect_failed")
    end
  end

  private

  def set_target_user
    if params[:user_id].present?
      policy = GoogleOauth::DelegateAccessPolicy.new(current_user: current_user)
      return redirect_to dashboard_root_path, alert: t(".#{policy.error}") unless policy.allowed?

      @target_user = current_account.users.find_by(id: params[:user_id])
      redirect_to dashboard_root_path, alert: t(".user_not_found") unless @target_user
    else
      @target_user = current_user
    end
  end

  def production_webhook_url
    return nil unless Rails.env.production?

    webhooks_google_calendar_url(host: request.host_with_port, protocol: request.protocol)
  end

  def extract_path(url)
    return nil if url.blank?
    URI.parse(url).path.presence
  rescue URI::InvalidURIError
    nil
  end
end
