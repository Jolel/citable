# frozen_string_literal: true

class Dashboard::BaseController < ApplicationController
  before_action :authenticate_user!

  layout "dashboard"

  private

  def current_account
    current_user.account
  end
  helper_method :current_account
end
