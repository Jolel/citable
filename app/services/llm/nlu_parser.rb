# frozen_string_literal: true

module Llm
  # Toolkit for extracting structured booking intent from free-text Spanish WhatsApp messages.
  module NluParser
    extend Dry::Monads[:result]

    MIN_CONFIDENCE = 0.8

    DATETIME_SCHEMA = {
      type: "object",
      properties: {
        starts_at:  { type: "string",  nullable: true,
                      description: "ISO 8601 datetime (YYYY-MM-DDTHH:MM:SS) or null" },
        confidence: { type: "number",
                      description: "0..1 — how certain the extraction is" }
      },
      required: [ "starts_at", "confidence" ]
    }.freeze

    SERVICE_SCHEMA = {
      type: "object",
      properties: {
        service_index: { type: "integer", nullable: true,
                         description: "1-based index of the matched service, or null" },
        confidence:    { type: "number",
                         description: "0..1 — how certain the match is" }
      },
      required: [ "service_index", "confidence" ]
    }.freeze

    CONFIRMATION_SCHEMA = {
      type: "object",
      properties: {
        decision:   { type: "string", nullable: true,
                      description: '"confirmed" if the customer accepts the booking, "cancelled" if they decline, null if unclear' },
        confidence: { type: "number",
                      description: "0..1 — how certain the interpretation is" }
      },
      required: %w[decision confidence]
    }.freeze

    # Returns Success({ value: Time, input_tokens:, output_tokens:, model: })
    # or Failure(:low_confidence | :llm_error).
    def self.parse_datetime(body, llm: Citable::Container["infrastructure.llm"])
      today  = Time.zone.today.strftime("%Y-%m-%d")
      system = <<~PROMPT.strip
        Eres un asistente que extrae fechas y horas de mensajes en español mexicano.
        Hoy es #{today}. La zona horaria es America/Mexico_City (siempre UTC-6, sin horario de verano).
        Devuelve starts_at como ISO 8601 sin zona horaria (YYYY-MM-DDTHH:MM:SS).
        No incluyas "Z" ni offsets como "-05:00" o "-06:00"; el sistema lo interpretará en America/Mexico_City.
        Devuelve null si no puedes determinarlo con certeza.
        Devuelve confidence entre 0 y 1.
      PROMPT
      user = "Extrae la fecha y hora de: \"#{body}\""

      response   = llm.call(system: system, user: user, schema: DATETIME_SCHEMA)
      raw_time   = response.content["starts_at"]
      confidence = response.content["confidence"].to_f

      return Failure(:low_confidence) if raw_time.blank? || confidence < MIN_CONFIDENCE

      naive = raw_time.to_s.sub(/(Z|[+-]\d{2}:?\d{2})\z/, "")
      time  = Time.zone.parse(naive)
      return Failure(:low_confidence) unless time

      Success({ value: time, input_tokens: response.input_tokens,
                output_tokens: response.output_tokens, model: response.model })
    rescue Llm::Port::Error => e
      Rails.logger.error "[Llm::NluParser] parse_datetime failed: #{e.message}"
      Failure(:llm_error)
    rescue ArgumentError, TypeError => e
      Rails.logger.error "[Llm::NluParser] parse_datetime parse error: #{e.message}"
      Failure(:llm_error)
    end

    # Returns Success({ value: Service, input_tokens:, output_tokens:, model: })
    # or Failure(:low_confidence | :llm_error).
    def self.parse_service(body, services, llm: Citable::Container["infrastructure.llm"])
      return Failure(:low_confidence) if services.empty?

      service_list = services.each_with_index.map { |svc, i| "#{i + 1}. #{svc.name}" }.join(", ")
      system = <<~PROMPT.strip
        Eres un asistente que identifica servicios en mensajes en español mexicano.
        Devuelve service_index (número 1-based) del servicio más probable, o null si no puedes determinarlo.
        Devuelve confidence entre 0 y 1.
      PROMPT
      user = "Servicios: #{service_list}. Mensaje: \"#{body}\". ¿Qué servicio quiere el cliente?"

      response   = llm.call(system: system, user: user, schema: SERVICE_SCHEMA)
      idx        = response.content["service_index"]
      confidence = response.content["confidence"].to_f

      return Failure(:low_confidence) if idx.nil? || confidence < MIN_CONFIDENCE

      service = services[idx.to_i - 1]
      return Failure(:low_confidence) unless service

      Success({ value: service, input_tokens: response.input_tokens,
                output_tokens: response.output_tokens, model: response.model })
    rescue Llm::Port::Error => e
      Rails.logger.error "[Llm::NluParser] parse_service failed: #{e.message}"
      Failure(:llm_error)
    rescue ArgumentError, TypeError => e
      Rails.logger.error "[Llm::NluParser] parse_service parse error: #{e.message}"
      Failure(:llm_error)
    end

    # Returns Success({ value: :confirmed | :cancelled, input_tokens:, output_tokens:, model: })
    # or Failure(:low_confidence | :llm_error).
    def self.parse_confirmation(body, llm: Citable::Container["infrastructure.llm"])
      system = <<~PROMPT.strip
        Eres un asistente que interpreta si un cliente acepta o rechaza una cita por WhatsApp, en español mexicano.
        Devuelve decision: "confirmed" si acepta (sí, si, dale, claro, va, ok, perfecto, confirmo, etc.),
        "cancelled" si rechaza (no, mejor no, cancela, no puedo, no gracias, etc.), o null si no es claro.
        Devuelve confidence entre 0 y 1.
      PROMPT
      user = "Mensaje del cliente: \"#{body}\""

      response   = llm.call(system: system, user: user, schema: CONFIRMATION_SCHEMA)
      decision   = response.content["decision"]
      confidence = response.content["confidence"].to_f

      return Failure(:low_confidence) if decision.nil? || confidence < MIN_CONFIDENCE

      decision_sym = decision == "confirmed" ? :confirmed : :cancelled
      Success({ value: decision_sym, input_tokens: response.input_tokens,
                output_tokens: response.output_tokens, model: response.model })
    rescue Llm::Port::Error => e
      Rails.logger.error "[Llm::NluParser] parse_confirmation failed: #{e.message}"
      Failure(:llm_error)
    end
  end
end
