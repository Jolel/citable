# frozen_string_literal: true

module TwilioWebhook
  class StartConversation
    include Dry::Monads[:result]

    def self.call(...) = new.call(...)

    def call(account:, from_phone:, customer:, profile_name: nil)
      @account = account
      @from_phone = from_phone

      resolved_customer = customer || create_customer_from_profile(profile_name)
      first_step = resolved_customer ? "awaiting_service" : "awaiting_name"

      conversation = account.whatsapp_conversations.create!(
        from_phone: from_phone,
        customer: resolved_customer,
        step: first_step
      )

      if resolved_customer
        send_service_greeting(conversation, resolved_customer)
      else
        send_name_prompt(conversation)
      end

      Success(conversation.step.to_sym)
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error "[TwilioWebhook::StartConversation] #{e.message}"
      Failure(:record_invalid)
    end

    private

    attr_reader :account, :from_phone

    # ── outbound helpers ──────────────────────────────────────────────────────

    # Known customer: LLM-personalised greeting + numbered service list,
    # falling back to the plain numbered list when the LLM is off or fails.
    def send_service_greeting(conversation, customer)
      message = llm_greeting(customer: customer) || fallback_service_list
      send_message(message, conversation: conversation, customer: customer)
    end

    # New customer: LLM-generated welcome that asks for their name,
    # falling back to the hardcoded prompt.
    def send_name_prompt(conversation)
      message = llm_greeting(customer: nil) ||
                "¡Hola! Para reservar tu cita, ¿cuál es tu nombre completo?"
      send_message(message, conversation: conversation)
    end

    # Returns an LLM-generated message string, or nil (caller must supply fallback).
    # Also stamps token usage on the most recent inbound log.
    def llm_greeting(customer:)
      return unless account.ai_nlu_enabled?

      result = Llm::GreetingGenerator.call(account: account, customer: customer)
      return unless result

      record_ai_usage(result)
      result.message
    end

    def fallback_service_list
      services = account.services.active.order(:name).each_with_index.map do |svc, index|
        "#{index + 1}. #{svc.name} (#{svc.duration_label})"
      end
      ([ "Elige un servicio:" ] + services).join("\n")
    end

    def send_message(message, conversation:, customer: nil, booking: nil)
      Whatsapp::MessageSender.call(
        account:  account,
        to:       from_phone,
        body:     message,
        booking:  booking,
        customer: customer || conversation.customer
      )
    end

    # ── LLM token logging ─────────────────────────────────────────────────────

    # result responds to: input_tokens, output_tokens, model.
    def record_ai_usage(result)
      log = account.message_logs.inbound.order(:created_at).last
      log&.update_columns(
        ai_input_tokens:  result.input_tokens,
        ai_output_tokens: result.output_tokens,
        ai_model:         result.model
      )
    end

    # ── customer helpers ──────────────────────────────────────────────────────

    def create_customer_from_profile(profile_name)
      return nil unless profile_name

      account.customers.create!(name: profile_name, phone: from_phone)
    end
  end
end
