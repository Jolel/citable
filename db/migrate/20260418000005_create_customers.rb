class CreateCustomers < ActiveRecord::Migration[8.1]
  def change
    create_table :customers do |t|
      t.references :account, null: false, foreign_key: true
      t.string :name, null: false
      t.string :phone, null: false
      t.text :notes
      t.jsonb :custom_fields, null: false, default: {}
      t.text :tags, array: true, null: false, default: []

      t.timestamps
    end

    add_index :customers, [ :account_id, :phone ]
    add_index :customers, :custom_fields, using: :gin
    add_index :customers, :tags, using: :gin
  end
end
