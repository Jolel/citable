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
    ALL_INTENTS = (QUESTION_INTENTS + BOOKING_CONTEXT_INTENTS + %w[cancel booking greeting other out_of_scope]).freeze

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

    def self.call(body, services:, account:, history: [], llm: Citable::Container["infrastructure.llm"])
      new(account: account, llm: llm).call(body, services, history)
    end

    def initialize(account:, llm: Citable::Container["infrastructure.llm"])
      @account = account
      @llm     = llm
    end

    # Returns Success({ intent:, service:, confidence:, input_tokens:, output_tokens:,
    #                   model:, latency_ms:, prompt_version: })
    # or Failure(:not_a_question | :llm_error).
    # Failure(:not_a_question) means the caller should fall through to the booking flow.
    def call(body, services, history = [])
      service_list = services.each_with_index.map { |svc, i| "#{i + 1}. #{svc.name}" }.join(", ")
      service_list = "(sin servicios)" if service_list.empty?

      tpl    = PromptTemplate.render(name: "question_classifier")
      system = tpl[:system] + history_section(history)
      user   = "Servicios disponibles: #{service_list}.\nMensaje del cliente: \"#{body}\"."

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

      Success({
        intent:         intent.to_sym,
        service:        service,
        confidence:     confidence,
        input_tokens:   response.input_tokens,
        output_tokens:  response.output_tokens,
        model:          response.model,
        latency_ms:     response.latency_ms,
        prompt_version: tpl[:version]
      })
    rescue Llm::Port::Error => e
      Rails.logger.warn "[Llm::QuestionClassifier] failed: #{e.message}"
      Failure(:llm_error)
    end

    private

    attr_reader :account

    def history_section(history)
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
  end
end
