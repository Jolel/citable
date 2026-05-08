# frozen_string_literal: true

module Llm
  # Extracts multiple booking slots (service, datetime, address, confirmation)
  # from a single free-text Spanish WhatsApp message in one LLM call.
  #
  # Replaces the previous pattern of calling NluParser.parse_service and
  # NluParser.parse_datetime separately — the customer message is parsed once,
  # and all available slots are returned together.  Slots that are absent or
  # below the per-slot confidence threshold are returned as nil; callers decide
  # what to ask for next.
  #
  # Returns Success({ slots: { service:, starts_at:, address:, confirmation: },
  #                   confidences: { service:, datetime:, address:, confirmation: },
  #                   top_candidates: [Service, ...],
  #                   input_tokens:, output_tokens:, model: })
  # or Failure(:llm_error).
  module BookingSlotExtractor
    extend Dry::Monads[:result]

    # Per-slot thresholds — service/confirmation are higher (booking errors are
    # expensive); datetime/address are slightly lower.
    SERVICE_MIN_CONFIDENCE      = 0.80
    DATETIME_MIN_CONFIDENCE     = 0.75
    ADDRESS_MIN_CONFIDENCE      = 0.70
    CONFIRMATION_MIN_CONFIDENCE = 0.80
    # Minimum confidence to include a service in top_candidates (Phase 4 use).
    SERVICE_CANDIDATE_THRESHOLD = 0.50

    SCHEMA = {
      type: "object",
      properties: {
        service_index: {
          type: "integer", nullable: true,
          description: "1-based index of the matched service, or null"
        },
        starts_at: {
          type: "string", nullable: true,
          description: "ISO 8601 datetime YYYY-MM-DDTHH:MM:SS (no zone) or null"
        },
        address: {
          type: "string", nullable: true,
          description: "Service address if explicitly mentioned, or null"
        },
        confirmation: {
          type: "string", nullable: true,
          enum: [ "confirmed", "cancelled" ],
          description: '"confirmed", "cancelled", or null'
        },
        confidences: {
          type: "object",
          properties: {
            service:      { type: "number", description: "0..1" },
            datetime:     { type: "number", description: "0..1" },
            address:      { type: "number", description: "0..1" },
            confirmation: { type: "number", description: "0..1" }
          },
          required: %w[service datetime address confirmation]
        },
        service_alternates: {
          type: "array",
          description: "Up to 2 alternative service matches when service confidence is 0.5–0.8",
          items: {
            type: "object",
            properties: {
              index:      { type: "integer" },
              confidence: { type: "number" }
            },
            required: %w[index confidence]
          }
        }
      },
      required: %w[service_index starts_at address confirmation confidences service_alternates]
    }.freeze

    # @param body      [String]              raw customer WhatsApp message
    # @param services  [Array<Service>]      account's active services (ordered)
    # @param today     [Date, nil]           override for today (defaults to Time.zone.today)
    # @param history   [Array<Hash>, nil]    conversation context from TurnHistory.for
    # @param llm       [Llm::Port]           injectable adapter
    def self.call(body:, services:, today: nil, history: [], llm: Citable::Container["infrastructure.llm"])
      today ||= Time.zone.today

      system = build_system_prompt(today, services, history)
      user   = "Mensaje del cliente: \"#{body}\""

      response = llm.call(system: system, user: user, schema: SCHEMA)
      parse_response(response, services)
    rescue Llm::Port::Error => e
      Rails.logger.error "[Llm::BookingSlotExtractor] LLM error: #{e.message}"
      Failure(:llm_error)
    rescue ArgumentError, TypeError => e
      Rails.logger.error "[Llm::BookingSlotExtractor] Parse error: #{e.message}"
      Failure(:llm_error)
    end

    # ── private helpers ──────────────────────────────────────────────────────

    def self.build_system_prompt(today, services, history = [])
      service_list = if services.empty?
                       "(sin servicios registrados)"
      else
                       services.each_with_index.map { |svc, i| "#{i + 1}. #{svc.name}" }.join(", ")
      end

      tomorrow    = (today + 1).strftime("%Y-%m-%d")
      day_name    = localized_day_name(today)
      next_fri    = next_weekday(today, 5).strftime("%Y-%m-%d")
      next_sat    = next_weekday(today, 6).strftime("%Y-%m-%d")
      next_mon    = next_weekday(today, 1).strftime("%Y-%m-%d")

      <<~PROMPT.strip
        Eres un asistente que extrae información de citas de mensajes en WhatsApp de clientes mexicanos.
        Hoy es #{today.strftime("%Y-%m-%d")} (#{day_name}). Zona horaria: America/Mexico_City (UTC-6, sin horario de verano).

        Servicios disponibles: #{service_list}

        Extrae todos los datos presentes en el mensaje:
        - service_index: número 1-based del servicio mencionado, o null si no se menciona ninguno
        - starts_at: ISO 8601 YYYY-MM-DDTHH:MM:SS (sin zona horaria) si se conocen TANTO fecha COMO hora, o null si falta alguno
        - address: dirección mencionada explícitamente, o null
        - confirmation: "confirmed" si el cliente acepta/confirma, "cancelled" si rechaza/cancela, null si no aplica
        - confidences: confianza 0-1 para cada campo (0.0 si el campo es null)
        - service_alternates: hasta 2 alternativas de servicio cuando la confianza de service esté entre 0.5 y 0.8

        Reglas para starts_at:
        - Devuelve null si solo se menciona la hora sin fecha ("como a las 3", "a las 5pm")
        - Devuelve null si solo se menciona el día sin hora ("el viernes", "el lunes que viene")
        - Devuelve null si la hora es ambigua en más de 30 minutos ("en la tarde", "en la mañana")
        - "mañana a las 3pm" → #{tomorrow}T15:00:00
        - NO incluyas "Z" ni offsets como "-06:00"; el sistema interpreta America/Mexico_City.#{history_block(history)}

        ## Ejemplos (servicios de ejemplo: 1. Corte clásico, 2. Tinte, 3. Manicure)

        ENTRADA: "Hola"
        SALIDA: {"service_index":null,"starts_at":null,"address":null,"confirmation":null,"confidences":{"service":0.0,"datetime":0.0,"address":0.0,"confirmation":0.0},"service_alternates":[]}

        ENTRADA: "quiero un corte el viernes a las 3"
        SALIDA: {"service_index":1,"starts_at":"#{next_fri}T15:00:00","address":null,"confirmation":null,"confidences":{"service":0.9,"datetime":0.88,"address":0.0,"confirmation":0.0},"service_alternates":[]}

        ENTRADA: "mañana a las 10am"
        SALIDA: {"service_index":null,"starts_at":"#{tomorrow}T10:00:00","address":null,"confirmation":null,"confidences":{"service":0.0,"datetime":0.93,"address":0.0,"confirmation":0.0},"service_alternates":[]}

        ENTRADA: "el viernes"
        SALIDA: {"service_index":null,"starts_at":null,"address":null,"confirmation":null,"confidences":{"service":0.0,"datetime":0.3,"address":0.0,"confirmation":0.0},"service_alternates":[]}

        ENTRADA: "como a las 3"
        SALIDA: {"service_index":null,"starts_at":null,"address":null,"confirmation":null,"confidences":{"service":0.0,"datetime":0.25,"address":0.0,"confirmation":0.0},"service_alternates":[]}

        ENTRADA: "quiero un corte normal mañana como a las 5"
        SALIDA: {"service_index":1,"starts_at":"#{tomorrow}T17:00:00","address":null,"confirmation":null,"confidences":{"service":0.85,"datetime":0.8,"address":0.0,"confirmation":0.0},"service_alternates":[]}

        ENTRADA: "lo del tinte para el sábado en la mañana"
        SALIDA: {"service_index":2,"starts_at":null,"address":null,"confirmation":null,"confidences":{"service":0.88,"datetime":0.35,"address":0.0,"confirmation":0.0},"service_alternates":[]}

        ENTRADA: "lo de siempre"
        SALIDA: {"service_index":null,"starts_at":null,"address":null,"confirmation":null,"confidences":{"service":0.25,"datetime":0.0,"address":0.0,"confirmation":0.0},"service_alternates":[]}

        ENTRADA: "sí, está bien"
        SALIDA: {"service_index":null,"starts_at":null,"address":null,"confirmation":"confirmed","confidences":{"service":0.0,"datetime":0.0,"address":0.0,"confirmation":0.93},"service_alternates":[]}

        ENTRADA: "mejor no gracias"
        SALIDA: {"service_index":null,"starts_at":null,"address":null,"confirmation":"cancelled","confidences":{"service":0.0,"datetime":0.0,"address":0.0,"confirmation":0.9},"service_alternates":[]}

        ENTRADA: "me lo pueden hacer en Insurgentes 123, el lunes a las 11"
        SALIDA: {"service_index":null,"starts_at":"#{next_mon}T11:00:00","address":"Insurgentes 123","confirmation":null,"confidences":{"service":0.0,"datetime":0.88,"address":0.9,"confirmation":0.0},"service_alternates":[]}

        ENTRADA: "quiero cortarme o hacerme las uñas el sábado a las 4pm"
        SALIDA: {"service_index":1,"starts_at":"#{next_sat}T16:00:00","address":null,"confirmation":null,"confidences":{"service":0.6,"datetime":0.9,"address":0.0,"confirmation":0.0},"service_alternates":[{"index":3,"confidence":0.58}]}
      PROMPT
    end
    private_class_method :build_system_prompt

    def self.parse_response(response, services)
      content     = response.content
      confidences = content["confidences"] || {}

      svc_conf = confidences["service"].to_f
      dt_conf  = confidences["datetime"].to_f
      adr_conf = confidences["address"].to_f
      cfm_conf = confidences["confirmation"].to_f

      service = if content["service_index"] && svc_conf >= SERVICE_MIN_CONFIDENCE
                  services[content["service_index"].to_i - 1]
      end

      starts_at = extract_datetime(content["starts_at"], dt_conf)

      address = if content["address"].present? && adr_conf >= ADDRESS_MIN_CONFIDENCE
                  content["address"]
      end

      confirmation = if cfm_conf >= CONFIRMATION_MIN_CONFIDENCE
                       case content["confirmation"]
                       when "confirmed" then :confirmed
                       when "cancelled" then :cancelled
                       end
      end

      top_candidates = extract_candidates(
        content["service_alternates"], services, content["service_index"]
      )

      Success({
        slots: {
          service:      service,
          starts_at:    starts_at,
          address:      address,
          confirmation: confirmation
        },
        confidences: {
          service:      svc_conf,
          datetime:     dt_conf,
          address:      adr_conf,
          confirmation: cfm_conf
        },
        top_candidates: top_candidates,
        input_tokens:   response.input_tokens,
        output_tokens:  response.output_tokens,
        model:          response.model
      })
    end
    private_class_method :parse_response

    def self.extract_datetime(raw, confidence)
      return nil if raw.blank? || confidence < DATETIME_MIN_CONFIDENCE

      # Strip any timezone suffix the LLM may have added despite instructions.
      naive = raw.to_s.sub(/(Z|[+-]\d{2}:?\d{2})\z/, "")
      Time.zone.parse(naive)
    rescue ArgumentError, TypeError
      nil
    end
    private_class_method :extract_datetime

    def self.extract_candidates(alternates, services, primary_index)
      return [] unless alternates.is_a?(Array)

      alternates
        .select { |a| a["confidence"].to_f >= SERVICE_CANDIDATE_THRESHOLD }
        .reject { |a| a["index"].to_i == primary_index.to_i }
        .first(2)
        .filter_map { |a| services[a["index"].to_i - 1] }
    end
    private_class_method :extract_candidates

    def self.history_block(history)
      return "" if history.blank?

      lines = history.filter_map do |entry|
        case entry[:role]
        when "user"      then "Cliente: #{entry[:body]}"
        when "assistant" then "Asistente: #{entry[:body]}"
        when "context"   then entry[:body]
        end
      end
      return "" if lines.empty?

      "\n\n## Contexto de la conversación\n#{lines.join("\n")}"
    end
    private_class_method :history_block

    def self.localized_day_name(date)
      I18n.t("date.day_names", locale: :"es-MX")[date.wday]
    rescue StandardError
      date.strftime("%A")
    end
    private_class_method :localized_day_name

    # Returns the next date that falls on +wday+ (0=Sun … 6=Sat).
    # If today is already that weekday, returns the NEXT occurrence (7 days out).
    def self.next_weekday(today, wday)
      days = (wday - today.wday) % 7
      days = 7 if days.zero?
      today + days
    end
    private_class_method :next_weekday
  end
end
