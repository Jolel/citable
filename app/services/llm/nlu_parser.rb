# frozen_string_literal: true

module Llm
  # Extracts structured booking intent from free-text Spanish WhatsApp messages.
  # Phase 1: parse_datetime and parse_service only (read-only NLU, no tool calls).
  class NluParser
    # Wraps the parsed value with token-usage metadata for logging.
    Result = Data.define(:value, :input_tokens, :output_tokens, :model)

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

    MIN_CONFIDENCE = 0.8

    def self.parse_datetime(body, account:)
      new(account: account).parse_datetime(body)
    end

    def self.parse_service(body, services, account:)
      new(account: account).parse_service(body, services)
    end

    def self.parse_confirmation(body, account:)
      new(account: account).parse_confirmation(body)
    end

    def initialize(account:)
      @account = account
    end

    # Returns Result(value: Time) or nil.
    def parse_datetime(body)
      today  = Time.zone.today.strftime("%Y-%m-%d")
      system = <<~PROMPT.strip
        Eres un asistente que extrae fechas y horas de mensajes en español mexicano.
        Hoy es #{today}. La zona horaria es America/Mexico_City.
        Devuelve starts_at como ISO 8601 (YYYY-MM-DDTHH:MM:SS), o null si no puedes determinarlo con certeza.
        Devuelve confidence entre 0 y 1.
      PROMPT
      user = "Extrae la fecha y hora de: \"#{body}\""

      result  = Llm::Client.call(system: system, user: user, schema: DATETIME_SCHEMA)
      parsed  = result[:content]
      raw_time = parsed["starts_at"]
      confidence = parsed["confidence"].to_f

      return nil if raw_time.blank? || confidence < MIN_CONFIDENCE

      time = Time.zone.parse(raw_time)
      return nil unless time

      Result.new(value: time,
                 input_tokens:  result[:input_tokens],
                 output_tokens: result[:output_tokens],
                 model:         result[:model])
    rescue Llm::Client::Error => e
      Rails.logger.warn "[Llm::NluParser] parse_datetime failed: #{e.message}"
      nil
    rescue ArgumentError, TypeError => e
      Rails.logger.warn "[Llm::NluParser] parse_datetime parse error: #{e.message}"
      nil
    end

    # Returns Result(value: Service) or nil.
    def parse_service(body, services)
      return nil if services.empty?

      service_list = services.each_with_index.map { |svc, i| "#{i + 1}. #{svc.name}" }.join(", ")
      system = <<~PROMPT.strip
        Eres un asistente que identifica servicios en mensajes en español mexicano.
        Devuelve service_index (número 1-based) del servicio más probable, o null si no puedes determinarlo.
        Devuelve confidence entre 0 y 1.
      PROMPT
      user = "Servicios: #{service_list}. Mensaje: \"#{body}\". ¿Qué servicio quiere el cliente?"

      result     = Llm::Client.call(system: system, user: user, schema: SERVICE_SCHEMA)
      parsed     = result[:content]
      idx        = parsed["service_index"]
      confidence = parsed["confidence"].to_f

      return nil if idx.nil? || confidence < MIN_CONFIDENCE

      service = services[idx.to_i - 1]
      return nil unless service

      Result.new(value: service,
                 input_tokens:  result[:input_tokens],
                 output_tokens: result[:output_tokens],
                 model:         result[:model])
    rescue Llm::Client::Error => e
      Rails.logger.warn "[Llm::NluParser] parse_service failed: #{e.message}"
      nil
    rescue ArgumentError, TypeError => e
      Rails.logger.warn "[Llm::NluParser] parse_service parse error: #{e.message}"
      nil
    end

    # Returns Result(value: :confirmed | :cancelled) or nil.
    def parse_confirmation(body)
      system = <<~PROMPT.strip
        Eres un asistente que interpreta si un cliente acepta o rechaza una cita por WhatsApp, en español mexicano.
        Devuelve decision: "confirmed" si acepta (sí, si, dale, claro, va, ok, perfecto, confirmo, etc.),
        "cancelled" si rechaza (no, mejor no, cancela, no puedo, no gracias, etc.), o null si no es claro.
        Devuelve confidence entre 0 y 1.
      PROMPT
      user = "Mensaje del cliente: \"#{body}\""

      result     = Llm::Client.call(system: system, user: user, schema: CONFIRMATION_SCHEMA)
      parsed     = result[:content]
      decision   = parsed["decision"]
      confidence = parsed["confidence"].to_f

      return nil if decision.nil? || confidence < MIN_CONFIDENCE

      decision_sym = decision == "confirmed" ? :confirmed : :cancelled
      Result.new(value:         decision_sym,
                 input_tokens:  result[:input_tokens],
                 output_tokens: result[:output_tokens],
                 model:         result[:model])
    rescue Llm::Client::Error => e
      Rails.logger.warn "[Llm::NluParser] parse_confirmation failed: #{e.message}"
      nil
    end

    private

    attr_reader :account
  end
end
