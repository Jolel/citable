# frozen_string_literal: true

class Dashboard::BaseController < ApplicationController
  before_action :authenticate_user!
  before_action :require_tenant!

  layout "dashboard"

  private

  def require_tenant!
    unless current_tenant
      redirect_to root_path, alert: "Negocio no encontrado."
    end
  end

  def current_account
    current_tenant
  end
  helper_method :current_account
end
