# frozen_string_literal: true

module TwilioWebhook
  # Handles inbound messages from a customer who already has an active upcoming
  # booking. Routes:
  #   "1" / "2" — confirms or cancels the booking and acks.
  #   Free text — classifies via Llm::QuestionClassifier:
  #     :cancel        → opens a confirming_cancellation conversation.
  #     :booking       → starts a new WhatsappConversation for a fresh booking.
  #     question intent → answers via TwilioWebhook::AnswerQuestion.
  #     anything else / LLM disabled → sends a safe fallback so we never go silent.
  class ProcessBookingReply
    include Dry::Monads[:result]

    def self.call(...) = new.call(...)

    def call(booking:, body:, account: nil, from_phone: nil, customer: nil)
      @booking    = booking
      @body       = body.to_s.strip
      @account    = account || booking.account
      @from_phone = from_phone || normalized_customer_phone
      @customer   = customer || booking.customer

      case @body
      when "1" then ack_confirmation
      when "2" then ack_cancellation
      else          handle_free_text
      end
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error "[TwilioWebhook::ProcessBookingReply] #{e.message}"
      Failure(:booking_update_failed)
    end

    private

    attr_reader :account, :body, :booking, :customer, :from_phone

    # ── 1 / 2 paths ───────────────────────────────────────────────────────────

    def ack_confirmation
      booking.confirm!
      send_message("Listo, tu cita quedó confirmada para #{format_starts_at}.")
      Success(booking)
    end

    def ack_cancellation
      booking.cancel!
      send_message("Listo, cancelé tu cita del #{format_starts_at}.")
      Success(booking)
    end

    # ── free text ─────────────────────────────────────────────────────────────

    def handle_free_text
      # Deterministic layer — always active regardless of ai_nlu_enabled.
      # Order matters: cancel check before other questions so "Quisiera cancelar"
      # is never misclassified as a price question.

      if IntentMatchers.cancellation_intent?(body)
        return open_cancellation_confirmation
      end

      if IntentMatchers.greeting_only?(body)
        send_message(fallback_message)
        return Success(:fallback_sent)
      end

      if IntentMatchers.asking_about_appointment_cost?(body)
        answer = AnswerQuestion.call(
          intent: :price, service: nil, account: account,
          cta: nil, booking: booking, customer: customer
        )
        send_message(answer)
        return Success(:answered_question)
      end

      if IntentMatchers.asking_about_appointment_date?(body) || IntentMatchers.asking_to_list_appointments?(body)
        answer = AnswerQuestion.call(
          intent: :appointment_date, service: nil, account: account,
          cta: nil, booking: booking, customer: customer
        )
        send_message(answer)
        return Success(:answered_question)
      end

      if IntentMatchers.asking_about_hours?(body)
        answer = AnswerQuestion.call(intent: :hours, service: nil, account: account, cta: nil)
        send_message(answer)
        return Success(:answered_question)
      end

      if IntentMatchers.asking_about_services?(body)
        answer = AnswerQuestion.call(intent: :services_list, service: nil, account: account, cta: nil)
        send_message(answer)
        return Success(:answered_question)
      end

      if IntentMatchers.asking_about_address?(body)
        answer = AnswerQuestion.call(intent: :address, service: nil, account: account, cta: nil)
        send_message(answer)
        return Success(:answered_question)
      end

      # AI classifier for remaining intents (booking re-schedule, specific price
      # queries by service name, etc.).
      classification = classify

      case classification && classification[:intent]
      when :cancel
        open_cancellation_confirmation
      when :booking
        delegate_to_start_conversation
      when :services_list, :price, :duration, :hours, :address,
           :appointment_date, :list_appointments
        answer_question(classification)
      else
        send_message(fallback_message)
        Success(:fallback_sent)
      end
    end

    def classify
      return nil if body.blank?
      return nil unless account.ai_nlu_enabled?
      return nil if from_phone.blank?

      services = account.services.active.order(:name)
      result = Llm::QuestionClassifier.call(body, services:, account:)
      return nil unless result.success?

      hash = result.value!
      return nil unless Llm::QuestionClassifier::POST_BOOKING_INTENTS.include?(hash[:intent].to_s)

      record_ai_usage(hash)
      hash
    end

    def open_cancellation_confirmation
      conversation = account.whatsapp_conversations.create!(
        from_phone: from_phone,
        customer:   customer,
        booking:    booking,
        step:       "confirming_cancellation"
      )
      send_message(
        "¿Seguro que quieres cancelar tu cita del #{format_starts_at}? " \
          "Responde 1 para confirmar la cancelación o 2 para mantenerla."
      )
      Success(conversation)
    end

    def delegate_to_start_conversation
      StartConversation.call(
        account:    account,
        from_phone: from_phone,
        customer:   customer,
        body:       body
      )
    end

    def answer_question(classification)
      message = AnswerQuestion.call(
        intent:   classification[:intent],
        service:  classification[:service],
        account:  account,
        cta:      nil,
        booking:  booking,
        customer: customer
      )
      send_message(message)
      Success(:answered_question)
    end

    def fallback_message
      "Tienes una cita el #{format_starts_at}. " \
        "Responde 1 para confirmarla, 2 para cancelarla, o escribe tu pregunta."
    end

    # ── helpers ───────────────────────────────────────────────────────────────

    def send_message(message)
      Whatsapp::MessageSender.call(
        account:  account,
        to:       from_phone,
        body:     message,
        booking:  booking,
        customer: customer
      )
    end

    def format_starts_at
      booking.starts_at.in_time_zone(account.timezone).strftime("%d/%m/%Y %H:%M")
    end

    def normalized_customer_phone
      Account.normalize_whatsapp_number(customer&.phone || booking.customer&.phone)
    end

    def record_ai_usage(hash)
      log = account.message_logs.inbound.order(:created_at).last
      log&.update_columns(
        ai_input_tokens:  hash[:input_tokens],
        ai_output_tokens: hash[:output_tokens],
        ai_model:         hash[:model]
      )
    end
  end
end
