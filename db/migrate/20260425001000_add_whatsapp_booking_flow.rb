# frozen_string_literal: true

class AddWhatsappBookingFlow < ActiveRecord::Migration[8.1]
  def change
    add_column :accounts, :whatsapp_number, :string
    add_index :accounts, :whatsapp_number, unique: true

    create_table :whatsapp_conversations do |t|
      t.references :account, null: false, foreign_key: true
      t.references :customer, foreign_key: true
      t.references :service, foreign_key: true
      t.references :booking, foreign_key: true
      t.string :from_phone, null: false
      t.string :step, null: false, default: "awaiting_name"
      t.datetime :requested_starts_at
      t.string :address
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :whatsapp_conversations, [ :account_id, :from_phone, :step ]
    add_index :whatsapp_conversations, :updated_at
  end
end
