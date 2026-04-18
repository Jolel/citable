class CreateReminderSchedules < ActiveRecord::Migration[8.1]
  def change
    create_table :reminder_schedules do |t|
      t.references :account, null: false, foreign_key: true
      t.references :booking, null: false, foreign_key: true
      t.string   :kind, null: false
      t.datetime :scheduled_for, null: false
      t.datetime :sent_at

      t.timestamps
    end

    add_index :reminder_schedules, [ :booking_id, :kind ], unique: true
    add_index :reminder_schedules, :scheduled_for
  end
end
