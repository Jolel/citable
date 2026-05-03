# frozen_string_literal: true

require "rails_helper"

RSpec.describe TwilioWebhook::HandleReply do
  # Several guided-flow examples send the literal "2026-04-26 15:00" prompt;
  # freeze "now" before that so starts_at_in_future accepts it.
  around { |ex| travel_to(Time.zone.local(2026, 4, 13, 9, 0)) { ex.run } }

  before do
    allow(GoogleCalendarSyncJob).to receive(:perform_later)
    allow(ReminderJob).to receive(:set).and_return(double(perform_later: true))
  end

  let(:account)  { create(:account) }
  let(:user)     { create(:user, account: account) }
  let(:service)  { create(:service, account: account) }
  let(:customer) { create(:customer, account: account, phone: "+5215512345678") }
  let!(:booking) do
    create(:booking, account: account, customer: customer, user: user, service: service,
           starts_at: 2.days.from_now, status: "pending")
  end

  before do
    account.update!(whatsapp_number: "whatsapp:+15551230000")
  end

  def call(from: "whatsapp:+5215512345678", to: "whatsapp:+15551230000", body: "1", profile_name: nil)
    described_class.call(from: from, to: to, body: body, profile_name: profile_name)
  end

  describe ".call" do
    context "when the business phone number is not recognized" do
      it "returns Success(:account_not_found)" do
        result = call(to: "whatsapp:+15550000000")
        expect(result).to be_success.and(have_attributes(value!: :account_not_found))
      end

      it "does not create a MessageLog" do
        expect { call(to: "whatsapp:+15550000000") }.not_to change(MessageLog, :count)
      end
    end

    context "when the customer phone number is not recognized" do
      it "starts a booking conversation asking for their name" do
        result = call(from: "whatsapp:+19990000000")
        expect(result).to be_success.and(have_attributes(value!: :awaiting_name))
      end

      it "creates an inbound and outbound MessageLog" do
        expect { call(from: "whatsapp:+19990000000") }.to change(MessageLog, :count).by(2)
      end
    end

    context "when the customer phone is not recognized but profile_name is present" do
      it "creates a customer and skips to service selection" do
        result = call(from: "whatsapp:+19990000000", profile_name: "Ana López")
        expect(result).to be_success.and(have_attributes(value!: :awaiting_service))
      end

      it "creates the customer with the profile name" do
        expect {
          call(from: "whatsapp:+19990000000", profile_name: "Ana López")
        }.to change(Customer, :count).by(1)

        expect(account.customers.last.name).to eq("Ana López")
      end
    end

    context "when the customer has no upcoming active booking" do
      before { booking.update_columns(starts_at: 2.days.ago, ends_at: 1.day.ago) }

      it "returns the service selection step" do
        result = call
        expect(result).to be_success.and(have_attributes(value!: :awaiting_service))
      end

      it "creates a booking conversation" do
        expect { call }.to change(WhatsappConversation, :count).by(1)
      end
    end

    context "when customer replies '1'" do
      it "returns Success with the booking" do
        result = call(body: "1")
        expect(result).to be_success.and(have_attributes(value!: booking))
      end

      it "confirms the booking" do
        call(body: "1")
        expect(booking.reload).to be_confirmed
      end

      it "creates an inbound whatsapp MessageLog" do
        expect { call(body: "1") }.to change(MessageLog, :count).by(1)

        log = MessageLog.last
        expect(log.channel).to eq("whatsapp")
        expect(log.direction).to eq("inbound")
        expect(log.status).to eq("delivered")
        expect(log.body).to eq("1")
        expect(log.customer).to eq(customer)
        expect(log.booking).to eq(booking)
        expect(log.account).to eq(account)
      end
    end

    context "when customer replies '2'" do
      it "returns Success with the booking" do
        result = call(body: "2")
        expect(result).to be_success.and(have_attributes(value!: booking))
      end

      it "cancels the booking" do
        call(body: "2")
        expect(booking.reload).to be_cancelled
      end

      it "creates an inbound whatsapp MessageLog" do
        expect { call(body: "2") }.to change(MessageLog, :count).by(1)
      end
    end

    context "when customer sends an unrecognized reply" do
      it "returns Success with the booking" do
        result = call(body: "hola")
        expect(result).to be_success.and(have_attributes(value!: booking))
      end

      it "does not change the booking status" do
        expect { call(body: "hola") }.not_to change { booking.reload.status }
      end

      it "still creates an inbound MessageLog" do
        expect { call(body: "hola") }.to change(MessageLog, :count).by(1)
      end
    end

    context "phone number matching" do
      it "matches when the from param includes the whatsapp: prefix" do
        result = call(from: "whatsapp:+5215512345678", body: "1")
        expect(result).to be_success.and(have_attributes(value!: booking))
      end

      it "matches on the last 10 digits regardless of country prefix" do
        result = call(from: "+5215512345678", body: "1")
        expect(result).to be_success.and(have_attributes(value!: booking))
      end
    end

    context "when two businesses have the same customer phone" do
      it "confirms only the booking scoped to the inbound business number" do
        other_account = create(:account, whatsapp_number: "whatsapp:+15559990000")
        other_user = create(:user, account: other_account)
        other_service = create(:service, account: other_account)
        other_customer = create(:customer, account: other_account, phone: "+5215512345678")
        other_booking = create(:booking, account: other_account, customer: other_customer,
                                         user: other_user, service: other_service,
                                         starts_at: 3.days.from_now, status: "pending")

        call(to: "whatsapp:+15559990000", body: "1")

        expect(other_booking.reload).to be_confirmed
        expect(booking.reload).to be_pending
      end
    end

    context "guided booking flow" do
      let!(:owner) { create(:user, :owner, account: account, name: "Owner") }

      it "creates a customer and booking from whatsapp prompts (no profile name)" do
        expect {
          call(from: "whatsapp:+5215599999999", body: "hola")
          call(from: "whatsapp:+5215599999999", body: "Rosa Martinez")
          call(from: "whatsapp:+5215599999999", body: "1")
          call(from: "whatsapp:+5215599999999", body: "2026-04-26 15:00")
          call(from: "whatsapp:+5215599999999", body: "1")
        }.to change(Customer, :count).by(1)
         .and change(Booking, :count).by(1)

        customer = account.customers.find_by!(phone: "5215599999999")
        booking = account.bookings.order(:created_at).last

        expect(customer.name).to eq("Rosa Martinez")
        expect(booking.customer).to eq(customer)
        expect(booking.service).to eq(service)
        expect(booking.user).to eq(owner)
        expect(booking.starts_at).to eq(Time.zone.local(2026, 4, 26, 15, 0))
        expect(booking).to be_pending
      end

      it "creates a customer and booking using profile_name (skips name step)" do
        expect {
          call(from: "whatsapp:+5215588888888", body: "hola", profile_name: "Rosa Martinez")
          call(from: "whatsapp:+5215588888888", body: "1")
          call(from: "whatsapp:+5215588888888", body: "2026-04-26 15:00")
          call(from: "whatsapp:+5215588888888", body: "1")
        }.to change(Customer, :count).by(1)
         .and change(Booking, :count).by(1)

        customer = account.customers.find_by!(phone: "5215588888888")
        expect(customer.name).to eq("Rosa Martinez")
      end

      it "re-prompts when the customer chooses an invalid service" do
        call(from: "whatsapp:+5215599999999", body: "hola")
        call(from: "whatsapp:+5215599999999", body: "Rosa Martinez")

        result = call(from: "whatsapp:+5215599999999", body: "99")

        expect(result).to be_success.and(have_attributes(value!: :awaiting_service))
        expect(Booking.count).to eq(1)
        expect(MessageLog.last.body).to include("elige un servicio")
      end

      it "re-prompts when date and time cannot be parsed" do
        call(from: "whatsapp:+5215599999999", body: "hola")
        call(from: "whatsapp:+5215599999999", body: "Rosa Martinez")
        call(from: "whatsapp:+5215599999999", body: "1")

        result = call(from: "whatsapp:+5215599999999", body: "pronto")

        expect(result).to be_success.and(have_attributes(value!: :awaiting_datetime))
        expect(account.bookings.where(customer: account.customers.find_by(phone: "5215599999999"))).to be_empty
      end

      it "asks for address when selected service requires it" do
        service.update!(requires_address: true)

        call(from: "whatsapp:+5215599999999", body: "hola")
        call(from: "whatsapp:+5215599999999", body: "Rosa Martinez")
        call(from: "whatsapp:+5215599999999", body: "1")
        result = call(from: "whatsapp:+5215599999999", body: "26/04/2026 15:00")

        expect(result).to be_success.and(have_attributes(value!: :awaiting_address))
        expect(MessageLog.last.body).to include("dirección")
      end
    end

    context "when an unexpected error is raised" do
      before { allow(Account).to receive(:find_by).and_raise(StandardError, "db exploded") }

      it "returns Failure(:processing_error)" do
        result = call
        expect(result).to be_failure.and(have_attributes(failure: :processing_error))
      end
    end
  end
end
