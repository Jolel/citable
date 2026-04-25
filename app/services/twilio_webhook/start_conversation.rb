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
        send_service_prompt(conversation)
      else
        send_message("¡Hola! Para reservar tu cita, ¿cuál es tu nombre completo?", conversation: conversation)
      end

      Success(conversation.step.to_sym)
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error "[TwilioWebhook::StartConversation] #{e.message}"
      Failure(:record_invalid)
    end

    private

    attr_reader :account, :from_phone

    def create_customer_from_profile(profile_name)
      return nil unless profile_name

      account.customers.create!(name: profile_name, phone: from_phone)
    end

    def send_service_prompt(conversation)
      services = account.services.active.order(:name).each_with_index.map do |svc, index|
        "#{index + 1}. #{svc.name} (#{svc.duration_label})"
      end
      send_message(([ "Elige un servicio:" ] + services).join("\n"), conversation: conversation, customer: conversation.customer)
    end

    def send_message(message, conversation:, customer: nil, booking: nil)
      Whatsapp::MessageSender.call(
        account: account,
        to: from_phone,
        body: message,
        booking: booking,
        customer: customer || conversation.customer
      )
    end
  end
end
