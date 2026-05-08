# frozen_string_literal: true

module TwilioWebhook
  # Detects mid-flow slot corrections ("espera, mejor el sábado a las 5") and
  # applies the updated slots to the conversation, rewinding the step to the
  # earliest step implied by what changed.
  #
  # Guard conditions (both must hold):
  # 1. Body contains a correction keyword (IntentMatchers.correction_intent?).
  # 2. At least one slot is already locked (service_id or requested_starts_at).
  #    This prevents false positives on first-turn messages like "mejor el lunes".
  #
  # Returns:
  #   Success({ rewound_to:, applied_slots:, input_tokens:, output_tokens:, model: })
  #   Failure(:no_correction | :no_locked_slots | :nothing_changed | :llm_error)
  class CorrectionDetector
    include Dry::Monads[:result]

    def self.call(body:, conversation:, account:, history: [])
      new.call(body: body, conversation: conversation, account: account, history: history)
    end

    def call(body:, conversation:, account:, history: [])
      return Failure(:no_correction)   unless IntentMatchers.correction_intent?(body)
      return Failure(:no_locked_slots) unless locked_slot?(conversation)

      services   = account.services.active.order(:name)
      extraction = Llm::BookingSlotExtractor.call(body: body, services: services, history: history)
      return Failure(:llm_error) unless extraction.success?

      new_slots = extraction.value![:slots]
      applied   = apply_changed_slots(new_slots, conversation)
      return Failure(:nothing_changed) if applied.empty?

      rewound_to = next_step_after_correction(applied, conversation)
      conversation.update!(step: rewound_to)

      Success({
        rewound_to:    rewound_to,
        applied_slots: applied,
        input_tokens:  extraction.value![:input_tokens],
        output_tokens: extraction.value![:output_tokens],
        model:         extraction.value![:model]
      })
    end

    private

    def locked_slot?(conversation)
      conversation.service_id.present? || conversation.requested_starts_at.present?
    end

    # Applies only the slots that actually changed. Returns symbols of what changed.
    def apply_changed_slots(slots, conversation)
      changed = []

      if (svc = slots[:service]) && svc != conversation.service
        conversation.service = svc
        changed << :service
      end

      if (dt = slots[:starts_at]) && dt != conversation.requested_starts_at
        conversation.requested_starts_at = dt
        changed << :starts_at
      end

      if (addr = slots[:address]).present? && addr != conversation.address
        conversation.address = addr
        changed << :address
      end

      conversation.save! if changed.any?
      changed
    end

    # Determines the appropriate next step after applying corrections.
    def next_step_after_correction(applied, conversation)
      if applied.include?(:service) && conversation.requested_starts_at.blank?
        return "awaiting_datetime"
      end

      svc = conversation.service
      if svc&.requires_address? && conversation.address.blank?
        return "awaiting_address"
      end

      "confirming_booking"
    end
  end
end
