# frozen_string_literal: true

class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  set_current_tenant_through_filter

  before_action :resolve_tenant

  private

  def resolve_tenant
    subdomain = request.subdomain
    return if subdomain.blank? || subdomain == "www"

    account = Account.find_by(subdomain: subdomain)
    set_current_tenant(account) if account
  end
end
