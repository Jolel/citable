# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Public::Bookings", type: :request do
  before do
    allow(GoogleCalendarSyncJob).to receive(:perform_later)
    allow(ReminderJob).to receive(:set).and_return(double(perform_later: true))
    allow(WhatsappSendJob).to receive(:perform_later)
  end

  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let!(:service) { create(:service, account: account, duration_minutes: 60) }

  describe "GET /reservar" do
    it "renders the booking form" do
      get public_booking_path
      expect(response).to have_http_status(:ok)
    end

    it "returns 404 when there is no account" do
      account.destroy!

      get public_booking_path

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /reservar" do
    let(:valid_params) do
      {
        booking: {
          service_id: service.id,
          user_id: user.id,
          starts_at: 2.days.from_now.change(hour: 10, min: 0).to_s
        },
        customer_name: "Luisa Flores",
        customer_phone: "+5215587654321"
      }
    end

    context "with valid params" do
      it "creates a booking" do
        expect {
          post public_booking_path, params: valid_params
        }.to change(Booking, :count).by(1)
      end

      it "creates or finds the customer by phone" do
        expect {
          post public_booking_path, params: valid_params
        }.to change(Customer, :count).by(1)
        expect(Customer.last.name).to eq("Luisa Flores")
      end

      it "enqueues a WhatsApp confirmation message" do
        post public_booking_path, params: valid_params
        expect(WhatsappSendJob).to have_received(:perform_later).with(anything, :confirmation)
      end

      it "redirects to the confirmation page" do
        post public_booking_path, params: valid_params
        expect(response).to redirect_to(
          public_booking_confirmation_path(id: Booking.last)
        )
      end

      it "reuses an existing customer with the same phone" do
        existing = create(:customer, account: account, phone: "+5215587654321")
        expect {
          post public_booking_path, params: valid_params
        }.not_to change(Customer, :count)
        expect(Booking.last.customer).to eq(existing)
      end
    end

    context "with invalid booking params (missing starts_at)" do
      let(:invalid_params) do
        {
          booking: {
            service_id: service.id,
            user_id: user.id,
            starts_at: ""
          },
          customer_name: "Luisa Flores",
          customer_phone: "+5215587654321"
        }
      end

      it "does not create a booking" do
        expect {
          post public_booking_path, params: invalid_params
        }.not_to change(Booking, :count)
      end

      it "renders the new template with 422" do
        post public_booking_path, params: invalid_params
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context "without an account" do
      it "returns 404" do
        account.destroy!

        post public_booking_path, params: {}

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "GET /reservar/confirmada/:id" do
    let!(:booking) do
      create(:booking, account: account, user: user, service: service,
             customer: create(:customer, account: account))
    end

    it "renders the confirmation page" do
      get public_booking_confirmation_path(id: booking.id)
      expect(response).to have_http_status(:ok)
    end
  end
end
