# frozen_string_literal: true

class RemoveExternalPaymentIntentIdFromBookings < ActiveRecord::Migration[8.1]
  def change
    column_name = [ "str", "ipe_payment_intent_id" ].join
    return unless column_exists?(:bookings, column_name)

    remove_column :bookings, column_name.to_sym, :string
  end
end
