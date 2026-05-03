# frozen_string_literal: true

class AddGoogleEventUniqueIndexToBookings < ActiveRecord::Migration[8.1]
  def change
    add_index :bookings, [ :account_id, :google_event_id ],
              unique: true,
              where: "google_event_id IS NOT NULL",
              name: "idx_bookings_account_google_event"
  end
end
