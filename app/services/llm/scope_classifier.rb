# frozen_string_literal: true

module Llm
  # Fallback classifier for messages that QuestionClassifier labelled "other"
  # but may still be legitimate questions the business should answer directly.
  # Runs only when the body has more than 2 words (skips bare "ok", "sí", etc.).
  #
  # Returns Success({ intent:, input_tokens:, output_tokens:, model: })
  # where intent is one of OUT_OF_SCOPE_TYPES, or Failure(:not_out_of_scope | :llm_error).
  module ScopeClassifier
    extend Dry::Monads[:result]

    OUT_OF_SCOPE_TYPES = %w[payment_question parking wifi amenity staff_question other_out_of_scope].freeze
    MIN_CONFIDENCE = 0.70

    SCHEMA = {
      type: "object",
      properties: {
        intent: {
          type: "string",
          enum: OUT_OF_SCOPE_TYPES + %w[other],
          description: "Type of out-of-scope question, or 'other' if not out-of-scope"
        },
        confidence: { type: "number", description: "0..1" }
      },
      required: %w[intent confidence]
    }.freeze

    def self.call(body:, account:, history: [], llm: Citable::Container["infrastructure.llm"])
      system = <<~PROMPT.strip
        Eres un clasificador de mensajes para negocios de servicios mexicanos.
        Determina si el mensaje es una pregunta fuera del alcance del asistente virtual.

        Categorías:
        - "payment_question": métodos de pago ("¿aceptan tarjeta?", "¿cobran con transferencia?", "¿hay descuento?")
        - "parking": estacionamiento o acceso ("¿hay estacionamiento?", "¿dónde me estaciono?")
        - "wifi": conectividad ("¿tienen wifi?", "¿cuál es la contraseña del wifi?")
        - "amenity": comodidades del local ("¿tienen área de espera?", "¿aceptan mascotas?", "¿hay acceso para sillas de ruedas?")
        - "staff_question": sobre el personal o negocio ("¿con quién voy?", "¿cuántos empleados tienen?", "¿quién es el dueño?")
        - "other_out_of_scope": otra pregunta legítima que el asistente no puede responder
        - "other": no es una pregunta fuera de alcance (es parte del flujo de reserva normal)

        Devuelve "other" si el mensaje es un saludo, confirmación, solicitud de cita, o pregunta sobre servicios, precios, horarios o dirección — esas las maneja el asistente directamente.#{history_section(history)}
      PROMPT
      user = "Mensaje del cliente: \"#{body}\""

      response   = llm.call(system: system, user: user, schema: SCHEMA)
      intent     = response.content["intent"]
      confidence = response.content["confidence"].to_f

      return Failure(:not_out_of_scope) if intent == "other" || confidence < MIN_CONFIDENCE
      return Failure(:not_out_of_scope) unless OUT_OF_SCOPE_TYPES.include?(intent)

      Success({
        intent:        intent.to_sym,
        input_tokens:  response.input_tokens,
        output_tokens: response.output_tokens,
        model:         response.model
      })
    rescue Llm::Port::Error => e
      Rails.logger.warn "[Llm::ScopeClassifier] failed: #{e.message}"
      Failure(:llm_error)
    end

    def self.history_section(history)
      return "" if history.blank?

      lines = history.filter_map do |entry|
        case entry[:role]
        when "user"      then "Cliente: #{entry[:body]}"
        when "assistant" then "Asistente: #{entry[:body]}"
        when "context"   then entry[:body]
        end
      end
      return "" if lines.empty?

      "\n\nContexto reciente:\n#{lines.join("\n")}"
    end
    private_class_method :history_section
  end
end
