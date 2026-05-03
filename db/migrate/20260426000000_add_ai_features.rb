# frozen_string_literal: true

class AddAiFeatures < ActiveRecord::Migration[8.1]
  def change
    add_column :accounts, :ai_nlu_enabled, :boolean, default: false, null: false

    add_column :message_logs, :ai_input_tokens, :integer
    add_column :message_logs, :ai_output_tokens, :integer
    add_column :message_logs, :ai_model, :string
  end
end
