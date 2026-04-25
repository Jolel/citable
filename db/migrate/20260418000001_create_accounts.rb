class CreateAccounts < ActiveRecord::Migration[8.1]
  def change
    create_table :accounts do |t|
      t.string :name, null: false
      t.string :timezone, null: false, default: "America/Mexico_City"
      t.string :locale, null: false, default: "es-MX"
      t.string :plan, null: false, default: "free"
      t.integer :whatsapp_quota_used, null: false, default: 0

      t.timestamps
    end
  end
end
