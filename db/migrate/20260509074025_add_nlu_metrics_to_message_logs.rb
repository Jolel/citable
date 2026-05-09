class AddNluMetricsToMessageLogs < ActiveRecord::Migration[8.1]
  def change
    add_column :message_logs, :ai_intent, :string
    add_column :message_logs, :ai_confidence, :decimal, precision: 5, scale: 4
    add_column :message_logs, :ai_latency_ms, :integer
    add_column :message_logs, :ai_prompt_version, :string
  end
end
