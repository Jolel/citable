# frozen_string_literal: true

module TwilioWebhook
  # Stamps LLM token usage onto the most recent inbound MessageLog for the
  # account.  Consolidates the identical record_ai_usage block that was
  # previously duplicated in AdvanceConversation, StartConversation, and
  # ProcessBookingReply.
  module AiUsageRecorder
    # hash must respond to [:input_tokens], [:output_tokens], [:model].
    def self.record(account:, hash:)
      return unless hash

      log = account.message_logs.inbound.order(:created_at).last
      log&.update_columns(
        ai_input_tokens:  hash[:input_tokens],
        ai_output_tokens: hash[:output_tokens],
        ai_model:         hash[:model]
      )
    end
  end
end
