# frozen_string_literal: true

module TwilioWebhook
  class AdvanceConversation
    include Dry::Monads[:result]

    def self.call(...) = new.call(...)

    def call(conversation:, body:, account:, from_phone:)
      @conversation = conversation
      @body = body
      @account = account
      @from_phone = from_phone

      # Deterministic checks first (always on, regardless of ai_nlu_enabled).
      # These handle the high-frequency "Hola" loop and common Q&A without an
      # LLM round-trip and without the non-determinism of confidence thresholds.
      if !confirmation_digit?(body)
        deterministic = maybe_answer_deterministically
        return deterministic if deterministic

        if IntentMatchers.greeting_only?(body)
          handle_mid_flow_greeting
          return Success(:greeted)
        end
      end

      if account.ai_nlu_enabled? && !confirmation_digit?(body)
        question_result = maybe_answer_question
        return question_result if question_result
      end

      case conversation.step
      when "awaiting_name"           then collect_name
      when "awaiting_service"        then collect_service
      when "awaiting_datetime"       then collect_datetime
      when "awaiting_address"        then collect_address
      when "confirming_booking"      then confirm_booking
      when "confirming_cancellation" then confirm_cancellation
      else
        Failure(:unknown_step)
      end
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error "[TwilioWebhook::AdvanceConversation] #{e.message}"
      Failure(:record_invalid)
    end

    private

    attr_reader :account, :body, :conversation, :from_phone

    def collect_name
      new_customer = account.customers.find_or_create_by!(phone: from_phone) do |record|
        record.name = body
      end
      new_customer.update!(name: body) if new_customer.name.blank?
      conversation.update!(customer: new_customer, step: "awaiting_service")
      send_service_prompt
      Success(:awaiting_service)
    end

    def collect_service
      idx     = service_index
      service = idx && idx >= 0 ? active_services[idx] : nil

      if service.nil? && account.ai_nlu_enabled?
        nlu = Llm::NluParser.parse_service(body, active_services)
        if nlu.success?
          record_ai_usage(nlu.value!)
          service = nlu.value![:value]
        end
      end

      unless service
        send_service_prompt(prefix: "No encontré esa opción. Por favor elige un servicio:")
        return Success(:awaiting_service)
      end

      conversation.update!(service: service, step: "awaiting_datetime")
      send_message(datetime_prompt, customer: conversation.customer)
      Success(:awaiting_datetime)
    end

    def collect_datetime
      starts_at = parse_datetime(body)

      if starts_at.nil? && account.ai_nlu_enabled?
        nlu = Llm::NluParser.parse_datetime(body)
        if nlu.success?
          record_ai_usage(nlu.value!)
          starts_at = nlu.value![:value]
        end
      end

      unless starts_at
        send_message(datetime_reprompt, customer: conversation.customer)
        return Success(:awaiting_datetime)
      end

      next_step = conversation.service.requires_address? ? "awaiting_address" : "confirming_booking"
      conversation.update!(requested_starts_at: starts_at, step: next_step)

      if conversation.service.requires_address?
        send_message("Este servicio requiere dirección. ¿Cuál es la dirección de la cita?", customer: conversation.customer)
        Success(:awaiting_address)
      else
        send_confirmation_prompt
        Success(:confirming_booking)
      end
    end

    def collect_address
      conversation.update!(address: body, step: "confirming_booking")
      send_confirmation_prompt
      Success(:confirming_booking)
    end

    def confirm_booking
      decision = rigid_decision || nlu_decision
      apply_decision(decision)
    end

    def confirm_cancellation
      booking = conversation.booking
      return Failure(:missing_booking) if booking.nil?

      decision = rigid_decision || nlu_decision
      case decision
      when :confirmed
        booking.cancel!
        conversation.update!(step: "completed")
        send_message("Listo, cancelé tu cita del #{format_starts_at(booking.starts_at)}.", customer: conversation.customer, booking: booking)
        Success(:cancelled_booking)
      when :cancelled
        conversation.update!(step: "completed")
        send_message("Perfecto, mantenemos tu cita del #{format_starts_at(booking.starts_at)}.", customer: conversation.customer, booking: booking)
        Success(:kept_booking)
      else
        send_message(
          "¿Seguro que quieres cancelar tu cita del #{format_starts_at(booking.starts_at)}? Responde 1 para confirmar la cancelación o 2 para mantenerla.",
          customer: conversation.customer,
          booking: booking
        )
        Success(:confirming_cancellation)
      end
    end

    def format_starts_at(time)
      time.in_time_zone(account.timezone).strftime("%d/%m/%Y %H:%M")
    end

    def rigid_decision
      case body
      when "1" then :confirmed
      when "2" then :cancelled
      end
    end

    def nlu_decision
      return unless account.ai_nlu_enabled?

      nlu = Llm::NluParser.parse_confirmation(body)
      return unless nlu.success?

      record_ai_usage(nlu.value!)
      nlu.value![:value]
    end

    def apply_decision(decision)
      case decision
      when :confirmed
        booking = create_booking
        conversation.update!(booking: booking)
        conversation.complete!
        send_message(
          "Listo, tu cita quedó solicitada. Te contactaremos por este medio si necesitamos ajustar algo.",
          customer: conversation.customer,
          booking: booking
        )
        Success(booking)
      when :cancelled
        conversation.update!(step: "cancelled")
        send_message("Sin problema, cancelé esta solicitud. Escríbenos de nuevo cuando quieras reservar.", customer: conversation.customer)
        Success(:cancelled)
      else
        send_confirmation_prompt(prefix: confirmation_hint)
        Success(:confirming_booking)
      end
    end

    def create_booking
      account.bookings.create!(
        customer: conversation.customer,
        service: conversation.service,
        user: staff_member,
        starts_at: conversation.requested_starts_at,
        address: conversation.address,
        status: "pending"
      )
    end

    def staff_member
      account.users.order(Arel.sql("CASE role WHEN 'owner' THEN 0 ELSE 1 END"), :name, :id).first
    end

    def active_services
      @active_services ||= account.services.active.order(:name).to_a
    end

    def service_index
      Integer(body) - 1
    rescue ArgumentError, TypeError
      nil
    end

    # Stamps AI token usage onto the most recent inbound log for the account.
    # nlu_hash is a plain Hash with keys :input_tokens, :output_tokens, :model.
    def record_ai_usage(nlu_hash)
      log = account.message_logs.inbound.order(:created_at).last
      log&.update_columns(
        ai_input_tokens:  nlu_hash[:input_tokens],
        ai_output_tokens: nlu_hash[:output_tokens],
        ai_model:         nlu_hash[:model]
      )
    end

    # ── prompt text helpers ───────────────────────────────────────────────────

    def datetime_prompt
      if account.ai_nlu_enabled?
        "¿Para cuándo quieres tu cita? Puedes escribirlo como quieras, " \
          "por ejemplo: el viernes a las 3, mañana a las 10am, el lunes próximo a las 5pm."
      else
        "Perfecto. ¿Qué fecha y hora quieres? " \
          "Ejemplos: #{Time.zone.today.strftime("%Y-%m-%d")} 15:00, " \
          "#{Time.zone.today.strftime("%d/%m/%Y")} 15:00 o mañana 15:00."
      end
    end

    def datetime_reprompt
      if account.ai_nlu_enabled?
        "No pude entender la fecha. ¿Puedes escribirla de otra forma? " \
          "Por ejemplo: el viernes a las 3, mañana a las 10am, el próximo lunes."
      else
        "No pude entender la fecha. " \
          "Intenta con #{Time.zone.today.strftime("%Y-%m-%d")} 15:00 " \
          "o #{Time.zone.today.strftime("%d/%m/%Y")} 15:00."
      end
    end

    def confirmation_hint
      if account.ai_nlu_enabled?
        "Responde 1 o escribe sí para confirmar, 2 o no para cancelar."
      else
        "Responde 1 para confirmar o 2 para cancelar."
      end
    end

    def parse_datetime(value)
      text = value.to_s.strip.downcase

      if text.match?(/\A(?:mañana|manana)\s+\d{1,2}:\d{2}\z/)
        time = text.split.last
        hour, minute = time.split(":").map(&:to_i)
        return (Time.zone.today + 1.day).in_time_zone.change(hour: hour, min: minute)
      end

      parse_with_format(value, "%Y-%m-%d %H:%M") || parse_with_format(value, "%d/%m/%Y %H:%M")
    end

    def parse_with_format(value, format)
      Time.zone.strptime(value, format)
    rescue ArgumentError
      nil
    end

    # Deterministic regex layer — runs before LLM, always active.
    # Returns Success(:answered_question) if a FAQ pattern matched, nil otherwise.
    def maybe_answer_deterministically
      customer = conversation.customer

      intent =
        if IntentMatchers.asking_about_appointment_cost?(body) then :price
        elsif IntentMatchers.asking_about_services?(body)       then :services_list
        elsif IntentMatchers.asking_about_hours?(body)          then :hours
        elsif IntentMatchers.asking_about_address?(body)        then :address
        elsif IntentMatchers.asking_about_appointment_date?(body) then :appointment_date
        elsif IntentMatchers.asking_to_list_appointments?(body)   then :list_appointments
        end

      return nil unless intent

      answer = AnswerQuestion.call(
        intent: intent, service: nil, account: account,
        cta: current_step_prompt_text, customer: customer
      )
      send_message(answer, customer: customer)
      Success(:answered_question)
    end

    # Sends the current-step re-prompt with a brief greeting prefix so a bare
    # "Hola" in mid-flow gets an acknowledgement instead of silence.
    def handle_mid_flow_greeting
      prompt = current_step_prompt_text
      return unless prompt

      send_message(prompt, customer: conversation.customer)
    end

    def confirmation_digit?(body)
      %w[1 2].include?(body.to_s.strip)
    end

    # LLM-backed question classification — only runs when ai_nlu_enabled and
    # deterministic layer didn't match.
    # Returns Success(:answered_question) or nil.
    def maybe_answer_question
      answerable = Llm::QuestionClassifier::QUESTION_INTENTS +
                   Llm::QuestionClassifier::BOOKING_CONTEXT_INTENTS

      result = Llm::QuestionClassifier.call(body, services: active_services, account: account)
      return nil unless result.success?

      data = result.value!
      return nil unless answerable.include?(data[:intent].to_s)

      record_ai_usage(data)
      answer = AnswerQuestion.call(
        intent: data[:intent], service: data[:service], account: account,
        cta: current_step_prompt_text, customer: conversation.customer
      )
      send_message(answer, customer: conversation.customer)
      Success(:answered_question)
    end

    # Returns the re-prompt text for the current step.
    # Used as the CTA footer inside question answers (one outbound message).
    # confirming_booking uses the short hint to avoid repeating the full block.
    def current_step_prompt_text
      case conversation.step
      when "awaiting_name"
        "Para continuar, ¿cuál es tu nombre completo?"
      when "awaiting_service"
        lines = active_services.each_with_index.map { |svc, i| "#{i + 1}. #{svc.name} (#{svc.duration_label})" }
        ([ "Elige un servicio:" ] + lines).join("\n")
      when "awaiting_datetime"
        datetime_prompt
      when "awaiting_address"
        "Este servicio requiere dirección. ¿Cuál es la dirección de la cita?"
      when "confirming_booking"
        confirmation_hint
      when "confirming_cancellation"
        booking = conversation.booking
        return nil unless booking
        "Responde 1 para confirmar la cancelación o 2 para mantenerla."
      end
    end

    def send_service_prompt(prefix: "Elige un servicio:")
      services = active_services.each_with_index.map do |svc, index|
        "#{index + 1}. #{svc.name} (#{svc.duration_label})"
      end
      send_message(([ prefix ] + services).join("\n"), customer: conversation.customer)
    end

    def send_confirmation_prompt(prefix: nil)
      starts_at = conversation.requested_starts_at.in_time_zone(account.timezone).strftime("%d/%m/%Y %H:%M")
      lines = []
      lines << prefix if prefix.present?
      lines << "Confirma tu cita:"
      lines << "#{conversation.service.name} - #{starts_at}"
      lines << "Dirección: #{conversation.address}" if conversation.address.present?
      lines << confirmation_hint
      send_message(lines.join("\n"), customer: conversation.customer)
    end

    def send_message(message, customer: nil, booking: nil)
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
