class CreateMessageLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :message_logs do |t|
      t.references :account, null: false, foreign_key: true
      t.references :booking, foreign_key: true
      t.references :customer, foreign_key: true
      t.string :channel, null: false
      t.string :direction, null: false
      t.text   :body, null: false
      t.string :status, null: false, default: "pending"
      t.string :external_id

      t.timestamps
    end

    add_index :message_logs, [ :account_id, :created_at ]
    add_index :message_logs, :external_id
  end
end
