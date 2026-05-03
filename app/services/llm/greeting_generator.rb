# frozen_string_literal: true

module Llm
  # Generates the conversational intro text for a new WhatsApp conversation.
  # Used by TwilioWebhook::StartConversation.
  #
  # Intentionally generates ONLY the greeting sentence(s) — not the service list.
  # The caller (StartConversation) appends the Rails-formatted numbered list so
  # that line breaks are guaranteed regardless of what the LLM returns.
  #
  # For a known customer: short personalised greeting (1–2 sentences).
  # For a new customer:   short welcome + ask for their full name.
  #
  # Returns Success({ message:, input_tokens:, output_tokens:, model: })
  # or Failure(:blank_message | :llm_error). Caller must supply a hardcoded fallback.
  class GreetingGenerator
    include Dry::Monads[:result]

    SCHEMA = {
      type: "object",
      properties: {
        message: { type: "string",
                   description: "Short greeting in Mexican Spanish, 1–2 sentences only. Do NOT include a service list." }
      },
      required: %w[message]
    }.freeze

    def self.call(llm: Citable::Container["infrastructure.llm"], **kwargs)
      new(llm: llm).call(**kwargs)
    end

    def initialize(llm: Citable::Container["infrastructure.llm"])
      @llm = llm
    end

    def call(account:, customer: nil)
      response = @llm.call(
        system: system_prompt(account),
        user:   user_prompt(customer: customer, account: account),
        schema: SCHEMA
      )

      message = response.content["message"]
      return Failure(:blank_message) if message.blank?

      Success({ message: message, input_tokens: response.input_tokens,
                output_tokens: response.output_tokens, model: response.model })
    rescue Llm::Port::Error => e
      Rails.logger.warn "[Llm::GreetingGenerator] #{e.message}"
      Failure(:llm_error)
    end

    private

    def system_prompt(account)
      <<~PROMPT.strip
        Eres la recepcionista virtual de "#{account.name}" en WhatsApp.
        Respondes en español mexicano con trato amable y cercano (tuteo).
        Escribe SOLO el saludo inicial — máx. 2 oraciones. Sin listas, sin opciones.
        Usa un emoji como mucho.
      PROMPT
    end

    def user_prompt(customer:, account:)
      if customer
        "El cliente se llama #{customer.name}. Escribe un saludo corto y personalizado. " \
          "No incluyas la lista de servicios; se agrega automáticamente después."
      else
        "Es un cliente nuevo de #{account.name}. " \
          "Escribe un saludo de bienvenida breve y pide su nombre completo."
      end
    end
  end
end
