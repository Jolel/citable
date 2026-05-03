# frozen_string_literal: true

class AddConfirmationTokenToBookings < ActiveRecord::Migration[8.1]
  def up
    add_column :bookings, :confirmation_token, :string
    add_index  :bookings, :confirmation_token, unique: true

    Booking.reset_column_information
    Booking.where(confirmation_token: nil).find_each(&:regenerate_confirmation_token)
  end

  def down
    remove_index  :bookings, :confirmation_token
    remove_column :bookings, :confirmation_token
  end
end
