# frozen_string_literal: true

module TwilioWebhook
  # Renders a deterministic Spanish answer for a classified customer question.
  # No LLM calls — all data comes from the account/services/bookings models.
  class AnswerQuestion
    DAY_KEYS = %w[mon tue wed thu fri sat sun].freeze
    DAY_LABELS = {
      "mon" => "Lunes", "tue" => "Martes", "wed" => "Miércoles", "thu" => "Jueves",
      "fri" => "Viernes", "sat" => "Sábado", "sun" => "Domingo"
    }.freeze
    BOOKING_CTA = "¿Quieres reservar una cita?"

    def self.call(intent:, service:, account:, cta: BOOKING_CTA, customer: nil, booking: nil)
      new(account: account).call(intent: intent, service: service, cta: cta, customer: customer, booking: booking)
    end

    def initialize(account:)
      @account = account
    end

    def call(intent:, service:, cta: BOOKING_CTA, customer: nil, booking: nil)
      body =
        case intent
        when :services_list      then services_list_answer
        when :price              then price_answer(service, booking)
        when :duration           then duration_answer(service)
        when :hours              then hours_answer
        when :address            then address_answer
        when :appointment_date   then appointment_date_answer(booking, customer)
        when :list_appointments  then list_appointments_answer(customer)
        else                          services_list_answer
        end

      cta.present? ? "#{body}\n\n#{cta}" : body
    end

    private

    attr_reader :account

    def active_services
      @active_services ||= account.services.active.order(:name)
    end

    def services_list_answer
      return "Aún no tenemos servicios publicados." if active_services.empty?

      lines = active_services.each_with_index.map do |svc, i|
        line = "#{i + 1}. #{svc.name} — #{svc.price.format} (#{svc.duration_label})"
        line += "\n   #{svc.description.strip}" if svc.description.present?
        line
      end
      ([ "Estos son nuestros servicios:" ] + lines).join("\n")
    end

    # When the customer asks "qué costo tendrá mi cita" we prefer the booked
    # service over the named service. Falls back to the explicit service or the
    # full services list.
    def price_answer(service, booking)
      svc = service || booking&.service
      return services_list_answer if svc.nil?

      "#{svc.name} cuesta #{svc.price.format} y dura #{svc.duration_label}."
    end

    def duration_answer(service)
      return services_list_answer if service.nil?

      "#{service.name} dura aproximadamente #{service.duration_label}."
    end

    def hours_answer
      hours = account.business_hours
      return "Aún no hemos publicado nuestros horarios. Mándanos un mensaje y con gusto te confirmamos." if hours.blank?

      lines = DAY_KEYS.map do |key|
        range = hours[key]
        if range.is_a?(Array) && range.length == 2 && range.all?(&:present?)
          "#{DAY_LABELS[key]}: #{range[0]}–#{range[1]}"
        else
          "#{DAY_LABELS[key]}: cerrado"
        end
      end
      ([ "Nuestros horarios:" ] + lines).join("\n")
    end

    def address_answer
      address = account.address.to_s.strip
      return "Aún no hemos publicado nuestra dirección. Mándanos un mensaje y con gusto te la compartimos." if address.blank?

      "Estamos en: #{address}."
    end

    def appointment_date_answer(booking, customer)
      relevant = booking || latest_upcoming_booking_for(customer)
      return "Por ahora no tienes citas próximas con nosotros." if relevant.nil?

      "Tu cita es el #{format_starts_at(relevant.starts_at)}#{relevant.service ? " para #{relevant.service.name}" : ""}."
    end

    def list_appointments_answer(customer)
      bookings = upcoming_bookings_for(customer)
      return "Por ahora no tienes citas próximas con nosotros." if bookings.empty?

      lines = bookings.map do |b|
        suffix = b.service ? " — #{b.service.name}" : ""
        "• #{format_starts_at(b.starts_at)}#{suffix}"
      end
      ([ "Estas son tus próximas citas:" ] + lines).join("\n")
    end

    def latest_upcoming_booking_for(customer)
      return nil unless customer

      account.bookings.active.upcoming.where(customer_id: customer.id).first
    end

    def upcoming_bookings_for(customer)
      return [] unless customer

      account.bookings.active.upcoming.where(customer_id: customer.id).limit(5).to_a
    end

    def format_starts_at(time)
      time.in_time_zone(account.timezone).strftime("%d/%m/%Y %H:%M")
    end
  end
end
