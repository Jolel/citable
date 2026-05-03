# frozen_string_literal: true

module PublicBookings
  class StaffPicker
    def self.call(account:, service: nil)
      new(account: account, service: service).call
    end

    def initialize(account:, service: nil)
      @account = account
      @service = service
    end

    def call
      @account.users
              .order(Arel.sql("CASE role WHEN 'owner' THEN 0 ELSE 1 END"), :name, :id)
              .first
    end
  end
end
