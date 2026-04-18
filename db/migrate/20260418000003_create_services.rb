class CreateServices < ActiveRecord::Migration[8.1]
  def change
    create_table :services do |t|
      t.references :account, null: false, foreign_key: true
      t.string  :name, null: false
      t.integer :duration_minutes, null: false, default: 60
      t.integer :price_cents, null: false, default: 0
      t.boolean :requires_address, null: false, default: false
      t.integer :deposit_amount_cents, null: false, default: 0
      t.boolean :active, null: false, default: true

      t.timestamps
    end

    add_index :services, [ :account_id, :name ]
  end
end
