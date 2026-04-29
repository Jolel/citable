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

      case conversation.step
      when "awaiting_name"      then collect_name
      when "awaiting_service"   then collect_service
      when "awaiting_datetime"  then collect_datetime
      when "awaiting_address"   then collect_address
      when "confirming_booking" then confirm_booking
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
        nlu = Llm::NluParser.parse_service(body, active_services, account: account)
        if nlu
          record_ai_usage(nlu)
          service = nlu.value
        end
      end

      unless service
        send_service_prompt(prefix: "No encontré esa opción. Por favor elige un servicio:")
        return Success(:awaiting_service)
      end

      conversation.update!(service: service, step: "awaiting_datetime")
      send_message(
        "Perfecto. ¿Qué fecha y hora quieres? Ejemplos: 2026-04-26 15:00, 26/04/2026 15:00 o mañana 15:00.",
        customer: conversation.customer
      )
      Success(:awaiting_datetime)
    end

    def collect_datetime
      starts_at = parse_datetime(body)

      if starts_at.nil? && account.ai_nlu_enabled?
        nlu = Llm::NluParser.parse_datetime(body, account: account)
        if nlu
          record_ai_usage(nlu)
          starts_at = nlu.value
        end
      end

      unless starts_at
        send_message("No pude entender la fecha. Intenta con 2026-04-26 15:00 o 26/04/2026 15:00.", customer: conversation.customer)
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
      case body
      when "1"
        booking = create_booking
        conversation.update!(booking: booking)
        conversation.complete!
        send_message(
          "Listo, tu cita quedó solicitada. Te contactaremos por este medio si necesitamos ajustar algo.",
          customer: conversation.customer,
          booking: booking
        )
        Success(booking)
      when "2"
        conversation.update!(step: "cancelled")
        send_message("Sin problema, cancelé esta solicitud. Escríbenos de nuevo cuando quieras reservar.", customer: conversation.customer)
        Success(:cancelled)
      else
        send_confirmation_prompt(prefix: "Responde 1 para confirmar o 2 para cancelar.")
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

    def record_ai_usage(nlu_result)
      log = account.message_logs
                   .inbound
                   .where(customer: conversation.customer)
                   .order(:created_at)
                   .last
      log&.update_columns(
        ai_input_tokens:  nlu_result.input_tokens,
        ai_output_tokens: nlu_result.output_tokens,
        ai_model:         nlu_result.model
      )
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
      lines << "Responde 1 para confirmar o 2 para cancelar."
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
