# frozen_string_literal: true

module Llm
  # Generates a warm, context-aware WhatsApp opening message in Mexican Spanish.
  # Used by TwilioWebhook::StartConversation when a new conversation begins.
  #
  # For a known customer: personalized greeting + numbered service list so the
  # customer can still reply "1" or type the service name freely.
  # For a new customer:   short welcome + ask for their name.
  #
  # Returns Result or nil (caller must supply a hardcoded fallback).
  class GreetingGenerator
    include Dry::Monads[:result]

    Result = Data.define(:message, :input_tokens, :output_tokens, :model)

    SCHEMA = {
      type: "object",
      properties: {
        message: { type: "string",
                   description: "WhatsApp message in Mexican Spanish, 3–4 lines max" }
      },
      required: %w[message]
    }.freeze

    def self.call(...) = new.call(...)

    def call(account:, customer: nil)
      llm_result = Llm::Client.call(
        system: system_prompt(account),
        user:   user_prompt(customer: customer, account: account),
        schema: SCHEMA
      )

      message = llm_result[:content]["message"]
      return nil if message.blank?

      Result.new(
        message:       message,
        input_tokens:  llm_result[:input_tokens],
        output_tokens: llm_result[:output_tokens],
        model:         llm_result[:model]
      )
    rescue Llm::Client::Error => e
      Rails.logger.warn "[Llm::GreetingGenerator] #{e.message}"
      nil
    end

    private

    def system_prompt(account)
      <<~PROMPT.strip
        Eres la recepcionista virtual de "#{account.name}" en WhatsApp.
        Respondes en español mexicano con trato amable y cercano.
        Tu único rol es ayudar a agendar, modificar o cancelar citas.
        Mantén el mensaje breve (máx. 4 líneas). Usa emojis con moderación (1 como mucho).
      PROMPT
    end

    def user_prompt(customer:, account:)
      if customer
        services = numbered_services(account)
        <<~PROMPT.strip
          El cliente se llama #{customer.name}. Escribe un saludo personalizado y luego muestra
          esta lista de servicios exactamente como aparece para que elija:
          #{services}
        PROMPT
      else
        "Es un cliente nuevo. Escribe un saludo de bienvenida a #{account.name} y pide su nombre completo."
      end
    end

    def numbered_services(account)
      account.services.active.order(:name).each_with_index.map do |svc, i|
        "#{i + 1}. #{svc.name} (#{svc.duration_label})"
      end.join("\n")
    end
  end
end
