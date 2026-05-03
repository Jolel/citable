# frozen_string_literal: true

require "rails_helper"

RSpec.describe TwilioWebhook::IntentMatchers do
  describe ".asking_about_appointment_cost?" do
    [
      "que costo tendra mi cita",
      "Que costo tendrá mi cita",
      "cuanto tendre que pagar",
      "cuánto tendré que pagar",
      "que costo tiene mi cita",
      "voy a pagar cuanto",
      "me va a costar cuanto",
      "cuánto vale mi cita"
    ].each do |body|
      it "matches #{body.inspect}" do
        expect(described_class.asking_about_appointment_cost?(body)).to be true
      end
    end

    [
      "Hola",
      "cuanto cuesta el corte de cabello",
      "que precio tiene el peinado especial"
    ].each do |body|
      it "does NOT match #{body.inspect}" do
        expect(described_class.asking_about_appointment_cost?(body)).to be false
      end
    end
  end

  describe ".asking_about_hours?" do
    [
      "cual es su horario",
      "Cuál es su horario",
      "Cual es el horario",
      "a que hora abren",
      "cuándo abren",
      "están abiertos"
    ].each do |body|
      it "matches #{body.inspect}" do
        expect(described_class.asking_about_hours?(body)).to be true
      end
    end
  end

  describe ".asking_about_services?" do
    [
      "Con que servicios cuentan",
      "con qué servicios cuentan",
      "que servicios tienen",
      "que ofrecen",
      "menu",
      "menú"
    ].each do |body|
      it "matches #{body.inspect}" do
        expect(described_class.asking_about_services?(body)).to be true
      end
    end
  end

  describe ".asking_about_address?" do
    [
      "Cual es la direccion",
      "cuál es la dirección",
      "donde están ubicados",
      "dónde están",
      "ubicación",
      "como llego",
      "donde queda"
    ].each do |body|
      it "matches #{body.inspect}" do
        expect(described_class.asking_about_address?(body)).to be true
      end
    end
  end

  describe ".asking_about_appointment_date?" do
    [
      "Cuando es mi cita",
      "cuándo es mi cita",
      "cuando tengo mi cita",
      "fecha de mi cita",
      "Me podrias recordar la fecha de mi cita",
      "recordarme la cita"
    ].each do |body|
      it "matches #{body.inspect}" do
        expect(described_class.asking_about_appointment_date?(body)).to be true
      end
    end
  end

  describe ".asking_to_list_appointments?" do
    [
      "Tengo citas",
      "tengo cita",
      "mis citas"
    ].each do |body|
      it "matches #{body.inspect}" do
        expect(described_class.asking_to_list_appointments?(body)).to be true
      end
    end
  end

  describe ".greeting_only?" do
    [
      "Hola",
      "hola",
      "HOLA",
      "Holaaa",
      "Buenas",
      "buenas tardes",
      "qué tal",
      "Hola!",
      "  hola  "
    ].each do |body|
      it "matches #{body.inspect}" do
        expect(described_class.greeting_only?(body)).to be true
      end
    end

    [
      "Hola, quiero un corte",
      "buenas tardes, agendo cita",
      "tengo dudas",
      "hola y cuanto cuesta"
    ].each do |body|
      it "does NOT match #{body.inspect} (has additional content)" do
        expect(described_class.greeting_only?(body)).to be false
      end
    end
  end

  describe ".cancellation_intent?" do
    [
      "Quisiera cancelar mi cita",
      "Cancelar",
      "cancela mi cita",
      "anular cita",
      "ya no puedo",
      "no voy a poder",
      "no podré ir"
    ].each do |body|
      it "matches #{body.inspect}" do
        expect(described_class.cancellation_intent?(body)).to be true
      end
    end
  end

  describe ".affirmative? / .negative?" do
    it "matches sí/no variants" do
      %w[sí si Si SI Sí confirmo Confirmar dale va listo].each do |body|
        expect(described_class.affirmative?(body)).to be(true), "expected #{body.inspect} to be affirmative"
      end

      %w[no nop nel].each do |body|
        expect(described_class.negative?(body)).to be(true), "expected #{body.inspect} to be negative"
      end
    end
  end
end
