class CreateRecurrenceRules < ActiveRecord::Migration[8.1]
  def change
    create_table :recurrence_rules do |t|
      t.references :account, null: false, foreign_key: true
      t.string  :frequency, null: false
      t.integer :interval, null: false, default: 1
      t.date    :ends_on

      t.timestamps
    end
  end
end
