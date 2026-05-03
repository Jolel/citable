# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Public::Bookings", type: :request do
  before do
    allow(GoogleCalendarSyncJob).to receive(:perform_later)
    allow(ReminderJob).to receive(:set).and_return(double(perform_later: true))
    allow(WhatsappSendJob).to receive(:perform_later)
  end

  let(:account) { create(:account, whatsapp_number: "5215512345678") }
  let!(:owner) { create(:user, account: account, role: "owner") }
  let!(:service) { create(:service, account: account, duration_minutes: 60) }

  describe "GET /r/:account_whatsapp/" do
    it "renders the booking form for a known account" do
      get public_booking_path(account_whatsapp: account.whatsapp_number)
      expect(response).to have_http_status(:ok)
    end

    it "returns 404 when the account has no matching whatsapp_number" do
      get public_booking_path(account_whatsapp: "9999999999")
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /r/:account_whatsapp/" do
    let(:valid_params) do
      {
        booking: {
          service_id: service.id,
          starts_at: 2.days.from_now.change(hour: 10, min: 0).to_s
        },
        customer_name: "Luisa Flores",
        customer_phone: "+5215587654321"
      }
    end

    context "with valid params" do
      it "creates a booking" do
        expect {
          post public_booking_path(account_whatsapp: account.whatsapp_number), params: valid_params
        }.to change(Booking, :count).by(1)
      end

      it "auto-assigns the owner as staff (does not honor user_id from params)" do
        other_account = create(:account, whatsapp_number: "5215599999999")
        intruder = create(:user, account: other_account, role: "staff")

        post public_booking_path(account_whatsapp: account.whatsapp_number),
             params: valid_params.deep_merge(booking: { user_id: intruder.id })

        expect(Booking.last.user).to eq(owner)
      end

      it "creates or finds the customer by phone" do
        expect {
          post public_booking_path(account_whatsapp: account.whatsapp_number), params: valid_params
        }.to change(Customer, :count).by(1)
        expect(Customer.last.name).to eq("Luisa Flores")
      end

      it "enqueues a WhatsApp confirmation message" do
        post public_booking_path(account_whatsapp: account.whatsapp_number), params: valid_params
        expect(WhatsappSendJob).to have_received(:perform_later).with(anything, :confirmation)
      end

      it "redirects to the confirmation page using the token, not the bigint id" do
        post public_booking_path(account_whatsapp: account.whatsapp_number), params: valid_params
        booking = Booking.last
        expect(booking.confirmation_token).to be_present
        expect(response).to redirect_to(
          public_booking_confirmation_path(
            account_whatsapp: account.whatsapp_number,
            token: booking.confirmation_token
          )
        )
      end

      it "reuses an existing customer with the same phone" do
        existing = create(:customer, account: account, phone: "+5215587654321")
        expect {
          post public_booking_path(account_whatsapp: account.whatsapp_number), params: valid_params
        }.not_to change(Customer, :count)
        expect(Booking.last.customer).to eq(existing)
      end
    end

    context "cross-tenant attack: service_id from another account" do
      let(:other_account) { create(:account, whatsapp_number: "5215599999999") }
      let!(:other_service) { create(:service, account: other_account) }

      it "rejects the booking and does not enqueue any jobs" do
        params = valid_params.deep_merge(booking: { service_id: other_service.id })

        expect {
          post public_booking_path(account_whatsapp: account.whatsapp_number), params: params
        }.not_to change(Booking, :count)

        expect(response).to have_http_status(:unprocessable_entity)
        expect(WhatsappSendJob).not_to have_received(:perform_later)
      end
    end

    context "backdated booking" do
      it "rejects bookings with past starts_at" do
        params = valid_params.deep_merge(booking: { starts_at: 1.year.ago.to_s })
        expect {
          post public_booking_path(account_whatsapp: account.whatsapp_number), params: params
        }.not_to change(Booking, :count)
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context "with invalid booking params (missing starts_at)" do
      let(:invalid_params) do
        {
          booking: {
            service_id: service.id,
            starts_at: ""
          },
          customer_name: "Luisa Flores",
          customer_phone: "+5215587654321"
        }
      end

      it "does not create a booking" do
        expect {
          post public_booking_path(account_whatsapp: account.whatsapp_number), params: invalid_params
        }.not_to change(Booking, :count)
      end

      it "renders the new template with 422" do
        post public_booking_path(account_whatsapp: account.whatsapp_number), params: invalid_params
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context "without an account" do
      it "returns 404" do
        post public_booking_path(account_whatsapp: "9999999999"), params: { booking: { starts_at: 1.day.from_now } }
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "GET /r/:account_whatsapp/confirmada/:token" do
    let!(:booking) do
      create(:booking, account: account, user: owner, service: service,
             customer: create(:customer, account: account))
    end

    it "renders the confirmation page when the token matches" do
      get public_booking_confirmation_path(
        account_whatsapp: account.whatsapp_number,
        token: booking.confirmation_token
      )
      expect(response).to have_http_status(:ok)
    end

    it "returns 404 for a numeric primary key (IDOR closed)" do
      expect {
        get public_booking_confirmation_path(
          account_whatsapp: account.whatsapp_number,
          token: booking.id.to_s
        )
      }.to raise_error(ActiveRecord::RecordNotFound)
    end

    it "returns 404 for a token from another account's booking" do
      other_account = create(:account, whatsapp_number: "5215599999999")
      other_owner = create(:user, account: other_account, role: "owner")
      other_service = create(:service, account: other_account)
      other_booking = create(:booking,
                             account: other_account,
                             user: other_owner,
                             service: other_service,
                             customer: create(:customer, account: other_account))

      expect {
        get public_booking_confirmation_path(
          account_whatsapp: account.whatsapp_number,
          token: other_booking.confirmation_token
        )
      }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end
end
