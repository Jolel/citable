# frozen_string_literal: true

class AddKindToMessageLogs < ActiveRecord::Migration[8.1]
  def change
    add_column :message_logs, :kind, :string
    add_index  :message_logs, [ :customer_id, :kind, :created_at ]
  end
end
