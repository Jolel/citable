class AddUniqueIndexToCustomersPhone < ActiveRecord::Migration[8.1]
  def change
    remove_index :customers, [ :account_id, :phone ]
    add_index :customers, [ :account_id, :phone ], unique: true
  end
end
