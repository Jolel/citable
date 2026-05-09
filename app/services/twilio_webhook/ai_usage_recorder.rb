# frozen_string_literal: true

module TwilioWebhook
  # Stamps LLM token usage and NLU metrics onto the most recent inbound
  # MessageLog for the account.
  #
  # Reads from hash: input_tokens, output_tokens, model (required);
  #   latency_ms, prompt_version, intent, confidence (optional).
  module AiUsageRecorder
    def self.record(account:, hash:)
      return unless hash

      log = account.message_logs.inbound.order(:created_at).last
      return unless log

      updates = {
        ai_input_tokens:  hash[:input_tokens],
        ai_output_tokens: hash[:output_tokens],
        ai_model:         hash[:model]
      }
      updates[:ai_latency_ms]     = hash[:latency_ms]           if hash.key?(:latency_ms)
      updates[:ai_prompt_version] = hash[:prompt_version]       if hash.key?(:prompt_version)
      updates[:ai_intent]         = hash[:intent]&.to_s         if hash.key?(:intent)
      updates[:ai_confidence]     = hash[:confidence]           if hash.key?(:confidence)

      log.update_columns(**updates)
    end
  end
end
