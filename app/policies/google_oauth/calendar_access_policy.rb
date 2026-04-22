# frozen_string_literal: true

module GoogleOauth
  class CalendarAccessPolicy
    attr_reader :error

    def initialize(current_user:, target_user:)
      @current_user = current_user
      @target_user  = target_user
    end

    def allowed?
      return true if @current_user.owner? || @current_user == @target_user

      @error = :access_denied
      false
    end
  end
end
