# frozen_string_literal: true

# Provides a `require_owner!` before_action helper. Including controllers
# opt in via `before_action :require_owner!` (optionally with :only/:except)
# so the concern can be applied either globally or to mutating actions only.
module Dashboard::OwnerOnly
  extend ActiveSupport::Concern

  private

  def require_owner!
    return if current_user&.owner?

    redirect_to dashboard_bookings_path, alert: "Acceso restringido."
  end
end
