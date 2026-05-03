# frozen_string_literal: true

require "rails_helper"

RSpec.describe TwilioWebhook::AnswerQuestion do
  let(:account) { create(:account) }
  let!(:corte) { create(:service, account: account, name: "Corte", price_cents: 25_000, duration_minutes: 60, description: "Incluye lavado.") }
  let!(:tinte) { create(:service, account: account, name: "Tinte", price_cents: 80_000, duration_minutes: 120) }

  describe "services_list" do
    it "lists active services with price, duration and CTA" do
      msg = described_class.call(intent: :services_list, service: nil, account: account)

      expect(msg).to include("Corte")
      expect(msg).to include("Tinte")
      expect(msg).to include("Incluye lavado.")
      expect(msg).to include("¿Quieres reservar una cita?")
    end
  end

  describe "price" do
    it "returns price + duration sentence for the named service" do
      msg = described_class.call(intent: :price, service: corte, account: account)

      expect(msg).to include("Corte cuesta")
      expect(msg).to include("1h")
      expect(msg).to include("¿Quieres reservar una cita?")
    end

    it "falls back to the services list when no service is given" do
      msg = described_class.call(intent: :price, service: nil, account: account)

      expect(msg).to include("Corte")
      expect(msg).to include("Tinte")
    end
  end

  describe "duration" do
    it "returns duration sentence for the named service" do
      msg = described_class.call(intent: :duration, service: tinte, account: account)

      expect(msg).to include("Tinte dura")
      expect(msg).to include("2h")
    end
  end

  describe "hours" do
    it "renders configured business hours in Spanish" do
      account.update!(business_hours: {
        "mon" => [ "09:00", "19:00" ], "tue" => [ "09:00", "19:00" ], "wed" => [ "09:00", "19:00" ],
        "thu" => [ "09:00", "19:00" ], "fri" => [ "09:00", "19:00" ], "sat" => [ "10:00", "14:00" ],
        "sun" => nil
      })

      msg = described_class.call(intent: :hours, service: nil, account: account)

      expect(msg).to include("Lunes: 09:00–19:00")
      expect(msg).to include("Sábado: 10:00–14:00")
      expect(msg).to include("Domingo: cerrado")
    end

    it "shows a friendly fallback when hours are not configured" do
      account.update!(business_hours: {})
      msg = described_class.call(intent: :hours, service: nil, account: account)

      expect(msg).to include("Aún no hemos publicado")
    end
  end

  describe "address" do
    it "returns the configured address" do
      account.update!(address: "Av. Reforma 100, CDMX")
      msg = described_class.call(intent: :address, service: nil, account: account)

      expect(msg).to include("Av. Reforma 100, CDMX")
    end

    it "shows a fallback when no address is configured" do
      account.update!(address: nil)
      msg = described_class.call(intent: :address, service: nil, account: account)

      expect(msg).to include("Aún no hemos publicado nuestra dirección")
    end
  end

  describe "price with booking context" do
    it "uses the booked service when no service is named" do
      customer = create(:customer, account: account)
      user = create(:user, account: account)
      booking = create(:booking, account: account, customer: customer, user: user, service: corte,
                                  starts_at: 1.day.from_now, status: "pending")

      msg = described_class.call(intent: :price, service: nil, account: account, booking: booking, cta: nil)

      expect(msg).to include("Corte cuesta")
    end
  end

  describe "appointment_date" do
    let(:customer) { create(:customer, account: account) }
    let(:user)     { create(:user, account: account) }

    it "returns the date of the booking when supplied" do
      booking = create(:booking, account: account, customer: customer, user: user, service: corte,
                                  starts_at: Time.zone.parse("2026-05-10 16:00"), status: "confirmed")

      msg = described_class.call(intent: :appointment_date, service: nil, account: account, booking: booking, cta: nil)

      expect(msg).to include("Tu cita es el")
      expect(msg).to include("10/05/2026 16:00")
      expect(msg).to include("Corte")
    end

    it "looks up the customer's upcoming booking when no booking is supplied" do
      create(:booking, account: account, customer: customer, user: user, service: tinte,
                       starts_at: 1.day.from_now, status: "pending")

      msg = described_class.call(intent: :appointment_date, service: nil, account: account, customer: customer, cta: nil)

      expect(msg).to include("Tu cita es el")
      expect(msg).to include("Tinte")
    end

    it "tells the customer they have no appointments when none exist" do
      msg = described_class.call(intent: :appointment_date, service: nil, account: account, customer: customer, cta: nil)

      expect(msg).to include("no tienes citas próximas")
    end
  end

  describe "list_appointments" do
    let(:customer) { create(:customer, account: account) }
    let(:user)     { create(:user, account: account) }

    it "lists up to 5 upcoming bookings" do
      create(:booking, account: account, customer: customer, user: user, service: corte,
                       starts_at: 1.day.from_now, status: "pending")
      create(:booking, account: account, customer: customer, user: user, service: tinte,
                       starts_at: 3.days.from_now, status: "confirmed")

      msg = described_class.call(intent: :list_appointments, service: nil, account: account, customer: customer, cta: nil)

      expect(msg).to include("Estas son tus próximas citas:")
      expect(msg).to include("Corte")
      expect(msg).to include("Tinte")
    end

    it "returns the no-citas message when the customer has none" do
      msg = described_class.call(intent: :list_appointments, service: nil, account: account, customer: customer, cta: nil)

      expect(msg).to include("no tienes citas próximas")
    end
  end
end
