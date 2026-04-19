class AddGoogleWatchFieldsToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :google_token_expires_at,   :datetime
    add_column :users, :google_channel_id,         :string
    add_column :users, :google_channel_expires_at, :datetime
    add_column :users, :google_sync_token,         :text
  end
end
