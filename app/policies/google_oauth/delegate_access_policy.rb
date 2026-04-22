# frozen_string_literal: true

module GoogleOauth
  class DelegateAccessPolicy
    attr_reader :error

    def initialize(current_user:)
      @current_user = current_user
    end

    def allowed?
      return true if @current_user.owner?

      @error = :access_denied
      false
    end
  end
end
