# frozen_string_literal: true

class AddAddressToAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :accounts, :address, :string
  end
end
