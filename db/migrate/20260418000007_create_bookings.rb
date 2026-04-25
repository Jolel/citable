class CreateBookings < ActiveRecord::Migration[8.1]
  def change
    create_table :bookings do |t|
      t.references :account, null: false, foreign_key: true
      t.references :customer, null: false, foreign_key: true
      t.references :service, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true, comment: "staff member assigned"
      t.references :recurrence_rule, foreign_key: true

      t.datetime :starts_at, null: false
      t.datetime :ends_at, null: false
      t.string   :status, null: false, default: "pending"
      t.string   :address
      t.string   :deposit_state, null: false, default: "not_required"
      t.datetime :confirmed_at
      t.string   :google_event_id

      t.timestamps
    end

    add_index :bookings, [ :account_id, :starts_at ]
    add_index :bookings, [ :user_id, :starts_at ]
    add_index :bookings, :status
  end
end
