# frozen_string_literal: true

module TwilioWebhook
  class StartConversation
    include Dry::Monads[:result]

    def self.call(...) = new.call(...)

    def call(account:, from_phone:, customer:, profile_name: nil, body: nil)
      phone = from_phone
      name = profile_name
      resolved_customer = customer || create_customer_from_profile(account:, phone:, name:)

      if (question = classify_question(account:, body:, customer: resolved_customer))
        answer_question(account:, phone:, customer: resolved_customer, question:)
        return Success(:answered_question)
      end

      first_step = resolved_customer ? "awaiting_service" : "awaiting_name"

      create_conversation(account:, phone:, customer: resolved_customer, step: first_step)
      if resolved_customer
        send_service_greeting(account:, phone:, customer: resolved_customer)
      else
        send_name_prompt(account:, phone:, customer: nil)
      end

      Success(first_step)
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error "[TwilioWebhook::StartConversation] #{e.message}"
      Failure(:record_invalid)
    end

    private

    def create_customer_from_profile(account:, phone:, name:)
      return nil unless name

      account.customers.create!(name:, phone:)
    end

    # Returns the unwrapped hash or nil. nil = not a question we answer;
    # caller falls through to normal booking greeting.
    def classify_question(account:, body:, customer:)
      return nil if body.blank?
      return nil unless account.ai_nlu_enabled?

      services = account.services.active.order(:name)
      history  = TurnHistory.for(account: account, customer: customer)
      result   = Llm::QuestionClassifier.call(body, services:, account:, history: history)
      return nil unless result.success?

      hash = result.value!
      all_answerable = Llm::QuestionClassifier::QUESTION_INTENTS
      all_answerable.include?(hash[:intent].to_s) ? hash : nil
    end

    def answer_question(account:, phone:, customer:, question:)
      TwilioWebhook::AiUsageRecorder.record(account: account, hash: question)
      message = AnswerQuestion.call(
        intent: question[:intent], service: question[:service],
        account: account, customer: customer
      )
      send_message(account:, to: phone, body: message, customer:)
    end

    def create_conversation(account:, phone:, customer:, step:)
      conversation = account.whatsapp_conversations.create!(
        from_phone: phone,
        customer:,
        step:
      )
    end

    # ── outbound helpers ──────────────────────────────────────────────────────

    # Known customer: LLM intro (1–2 sentences) followed by the Rails-formatted
    # service list. The list is always appended by Rails so line breaks are
    # guaranteed regardless of LLM output. Falls back to the plain list when
    # the LLM is off or unavailable.
    def send_service_greeting(account:, phone:, customer:)
      intro   = llm_greeting(account:, customer:)
      list    = fallback_service_list(account:)
      message = intro ? "#{intro}\n#{list}" : list
      send_message(account:, to: phone, body: message, customer:)
    end

    # New customer: LLM-generated welcome that asks for their name,
    # falling back to the hardcoded prompt.
    def send_name_prompt(account:, phone:, customer:)
      message = llm_greeting(account:, customer:) ||
                "¡Hola! Para reservar tu cita, ¿cuál es tu nombre completo?"
      send_message(account:, to: phone, body: message, customer:)
    end

    # Returns an LLM-generated message string, or nil (caller must supply fallback).
    # Also stamps token usage on the most recent inbound log.
    def llm_greeting(account:, customer:)
      return unless account.ai_nlu_enabled?

      result = Llm::GreetingGenerator.call(account:, customer:)
      return unless result.success?

      TwilioWebhook::AiUsageRecorder.record(account: account, hash: result.value!)
      result.value![:message]
    end

    def fallback_service_list(account:)
      services = account.services.active.order(:name).each_with_index.map do |svc, index|
        "#{index + 1}. #{svc.name} (#{svc.duration_label})"
      end
      ([ "Elige un servicio:" ] + services).join("\n")
    end

    def send_message(account:, to:, body:, customer: nil, booking: nil)
      Whatsapp::MessageSender.call(account:, to:, body:, customer:, booking:)
    end
  end
end
