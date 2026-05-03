# frozen_string_literal: true

module Llm
  # Classifies an inbound free-text WhatsApp message as a question (vs. booking
  # intent or other). Used at the start of a conversation to answer FAQs from
  # business data before falling through to the booking flow.
  class QuestionClassifier
    include Dry::Monads[:result]

    # Intents that AnswerQuestion can render without booking context.
    QUESTION_INTENTS = %w[services_list price duration hours address].freeze
    # Intents that require an active booking to answer (date of cita, list of citas).
    BOOKING_CONTEXT_INTENTS = %w[appointment_date list_appointments].freeze
    # Intents the post-booking handler reacts to (questions + flow control).
    POST_BOOKING_INTENTS = (QUESTION_INTENTS + BOOKING_CONTEXT_INTENTS + %w[cancel booking]).freeze
    ALL_INTENTS = (QUESTION_INTENTS + BOOKING_CONTEXT_INTENTS + %w[cancel booking greeting other]).freeze

    SCHEMA = {
      type: "object",
      properties: {
        intent: { type: "string", nullable: true,
                  enum: ALL_INTENTS,
                  description: "What the customer is asking about" },
        service_index: { type: "integer", nullable: true,
                         description: "1-based index of the referenced service when intent is price or duration" },
        confidence: { type: "number", description: "0..1 — how certain the classification is" }
      },
      required: %w[intent service_index confidence]
    }.freeze

    # Question miss is cheap (the bot re-prompts); booking miss is expensive
    # (wrong booking is created). Keep this lower than NluParser::MIN_CONFIDENCE.
    MIN_CONFIDENCE = 0.65

    def self.call(body, services:, account:, llm: Citable::Container["infrastructure.llm"])
      new(account: account, llm: llm).call(body, services)
    end

    def initialize(account:, llm: Citable::Container["infrastructure.llm"])
      @account = account
      @llm     = llm
    end

    # Returns Success({ intent:, service:, input_tokens:, output_tokens:, model: })
    # or Failure(:not_a_question | :llm_error).
    # Failure(:not_a_question) means the caller should fall through to the booking flow.
    def call(body, services)
      service_list = services.each_with_index.map { |svc, i| "#{i + 1}. #{svc.name}" }.join(", ")
      service_list = "(sin servicios)" if service_list.empty?

      system = <<~PROMPT.strip
        Eres un asistente que clasifica mensajes de clientes en WhatsApp para un negocio mexicano.
        Determina si el cliente está haciendo una pregunta o quiere reservar.

        Intents posibles:
        - "services_list": pregunta qué servicios ofrecen ("¿qué servicios tienen?", "qué hacen", "menú", "con qué cuentan")
        - "price": pregunta el precio de un servicio específico o el costo de su cita ("¿cuánto cuesta el corte?", "precio del tinte", "cuánto tendré que pagar", "qué costo tiene mi cita")
        - "duration": pregunta cuánto dura un servicio ("¿cuánto tarda?", "cuánto se lleva")
        - "hours": pregunta los horarios ("¿a qué hora abren?", "horarios", "están abiertos")
        - "address": pregunta dónde está el negocio ("¿cuál es la dirección?", "dónde están", "ubicación", "cómo llego")
        - "appointment_date": pregunta cuándo es SU PROPIA cita ("¿cuándo es mi cita?", "fecha de mi cita", "recuérdame mi cita")
        - "list_appointments": pregunta si tiene citas o cuáles tiene ("¿tengo citas?", "mis citas")
        - "cancel": el cliente quiere cancelar su cita ("cancelar mi cita", "ya no puedo", "no voy a poder ir", "anular")
        - "booking": el cliente quiere reservar una cita (menciona servicio + fecha/hora, o dice "quiero agendar")
        - "greeting": saludo simple sin contenido adicional ("hola", "buenas", "qué tal")
        - "other": mensaje no relacionado o ambiguo

        Para "price" y "duration", devuelve service_index (1-based) si el cliente menciona un servicio específico, o null si pregunta en general o sobre su propia cita.
        Devuelve confidence entre 0 y 1.
      PROMPT
      user = "Servicios disponibles: #{service_list}.\nMensaje del cliente: \"#{body}\"."

      response   = @llm.call(system: system, user: user, schema: SCHEMA)
      intent     = response.content["intent"]
      idx        = response.content["service_index"]
      confidence = response.content["confidence"].to_f

      return Failure(:not_a_question) if intent.nil? || confidence < MIN_CONFIDENCE
      return Failure(:not_a_question) unless ALL_INTENTS.include?(intent) && intent != "other"
      # Greeting is recognized for callers that want it (handled by IntentMatchers
      # too) but treated as fall-through here so the booking flow keeps moving.
      return Failure(:not_a_question) if intent == "greeting"

      service = idx && services[idx.to_i - 1]

      Success({ intent: intent.to_sym, service: service, input_tokens: response.input_tokens,
                output_tokens: response.output_tokens, model: response.model })
    rescue Llm::Port::Error => e
      Rails.logger.warn "[Llm::QuestionClassifier] failed: #{e.message}"
      Failure(:llm_error)
    end

    private

    attr_reader :account
  end
end
