# frozen_string_literal: true

module TwilioWebhook
  # Deterministic Spanish regex matchers for inbound WhatsApp intent detection.
  # These run before any LLM call so the bot stays responsive when the LLM is
  # disabled, slow, or non-deterministic on borderline confidence.
  module IntentMatchers
    extend self

    PRICE_WORDS = /\b(costo|costos|cuesta|cuestan|cuánto|cuanto|precio|precios|pagar|cobrar|vale|sale|costará|costara|tarifa|tarifas)\b/i

    OWN_APPOINTMENT_WORDS = /\b(mi\s+cita|la\s+cita|mi\s+reserva|la\s+reserva|mi\s+servicio|tendr[eéa]|tener\s+que\s+pagar|voy\s+a\s+pagar|me\s+va\s+a\s+costar)\b/i

    HOURS_WORDS = /\b(horario|horarios|a\s+qu[eé]\s+hora|qu[eé]\s+hora(?:s)?\s+(?:abren|cierran|atienden)|cu[aá]ndo\s+abren|cu[aá]ndo\s+cierran|abren|atienden|est[aá]n\s+abiertos)\b/i

    SERVICES_WORDS = /\b(servicios?|qu[eé]\s+hacen|qu[eé]\s+ofrecen|men[uú]|qu[eé]\s+tienen|con\s+qu[eé]\s+cuentan)\b/i

    ADDRESS_WORDS = /\b(direcci[oó]n|d[oó]nde\s+(?:est[aá]n|ubicad|queda|los?\s+encuentro)|ubicaci[oó]n|c[oó]mo\s+llego|d[oó]nde\s+se\s+encuentra)\b/i

    APPOINTMENT_DATE_WORDS = /\b(cu[aá]ndo\s+(?:es|tengo)\s+mi\s+cita|fecha\s+de\s+mi\s+cita|cu[aá]ndo\s+es\s+mi\s+(?:cita|reserva)|recordar(?:me)?\s+(?:la\s+)?(?:fecha|cita))\b/i

    LIST_APPOINTMENTS_WORDS = /\b(mis\s+citas|tengo\s+citas|tengo\s+(?:una\s+)?cita|tengo\s+alguna\s+cita)\b/i

    GREETING_ONLY = /\A\s*(hola+|holaa+|holi|holis|buenas|buenas\s+tardes|buenas\s+noches|buenos\s+d[ií]as|qu[eé]\s+tal|hey|saludos|ola)[\s.!¡]*\z/i

    CANCEL_WORDS = /\b(cancelar(?:me)?|cancela|cancelo|cancelaci[oó]n|anular|ya\s+no\s+(?:puedo|voy)|no\s+podr[eé](?:\s+ir)?|no\s+voy\s+a\s+poder|deseo\s+cancelar|quiero\s+cancelar|quisiera\s+cancelar)\b/i

    CONFIRM_YES = /\A\s*(s[ií](?:\s+confirmo)?|sip|simon|claro|dale|va|ok(?:ay)?|perfecto|de\s+acuerdo|confirmo|confirmar|confirmado|adelante|por\s+supuesto|listo)[\s.!¡]*\z/i

    CONFIRM_NO = /\A\s*(no(?:\s+gracias)?|nop|nel|cancela|mejor\s+no|no\s+puedo|no\s+quiero)[\s.!¡]*\z/i

    def asking_about_appointment_cost?(body)
      PRICE_WORDS.match?(body) && OWN_APPOINTMENT_WORDS.match?(body)
    end

    def asking_about_price?(body)
      PRICE_WORDS.match?(body)
    end

    def asking_about_hours?(body)
      HOURS_WORDS.match?(body)
    end

    def asking_about_services?(body)
      SERVICES_WORDS.match?(body)
    end

    def asking_about_address?(body)
      ADDRESS_WORDS.match?(body)
    end

    def asking_about_appointment_date?(body)
      APPOINTMENT_DATE_WORDS.match?(body)
    end

    def asking_to_list_appointments?(body)
      LIST_APPOINTMENTS_WORDS.match?(body)
    end

    # True only when the message is *just* a greeting (no other content).
    # Used to short-circuit "Hola" loops mid-flow without misclassifying
    # messages that happen to start with "hola".
    def greeting_only?(body)
      GREETING_ONLY.match?(body.to_s.strip)
    end

    def cancellation_intent?(body)
      CANCEL_WORDS.match?(body)
    end

    def affirmative?(body)
      CONFIRM_YES.match?(body.to_s.strip)
    end

    def negative?(body)
      CONFIRM_NO.match?(body.to_s.strip)
    end
  end
end
