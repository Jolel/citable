class CreateStaffAvailabilities < ActiveRecord::Migration[8.1]
  def change
    create_table :staff_availabilities do |t|
      t.references :account, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.integer :day_of_week, null: false
      t.time :start_time, null: false
      t.time :end_time, null: false
      t.boolean :active, null: false, default: true

      t.timestamps
    end

    add_index :staff_availabilities, [ :user_id, :day_of_week ]
  end
end
