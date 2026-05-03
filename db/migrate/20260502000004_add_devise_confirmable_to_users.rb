# frozen_string_literal: true

class AddDeviseConfirmableToUsers < ActiveRecord::Migration[8.1]
  def up
    add_column :users, :confirmation_token,   :string
    add_column :users, :confirmed_at,         :datetime
    add_column :users, :confirmation_sent_at, :datetime
    add_column :users, :unconfirmed_email,    :string

    add_index :users, :confirmation_token, unique: true

    User.reset_column_information
    User.where(confirmed_at: nil).update_all("confirmed_at = COALESCE(created_at, NOW())")
  end

  def down
    remove_index  :users, :confirmation_token
    remove_column :users, :confirmation_token
    remove_column :users, :confirmed_at
    remove_column :users, :confirmation_sent_at
    remove_column :users, :unconfirmed_email
  end
end
