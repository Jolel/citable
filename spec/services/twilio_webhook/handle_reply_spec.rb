# frozen_string_literal: true

require "rails_helper"

RSpec.describe TwilioWebhook::HandleReply do
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

  def call(from: "whatsapp:+5215512345678", body: "1")
    described_class.call(from: from, body: body)
  end

  describe ".call" do
    context "when the phone number is not recognized" do
      it "returns Success(:customer_not_found)" do
        result = call(from: "whatsapp:+19990000000")
        expect(result).to be_success.and(have_attributes(value!: :customer_not_found))
      end

      it "does not create a MessageLog" do
        expect { call(from: "whatsapp:+19990000000") }.not_to change(MessageLog, :count)
      end
    end

    context "when the customer has no upcoming active booking" do
      before { booking.update_columns(starts_at: 2.days.ago, ends_at: 1.day.ago) }

      it "returns Success(:no_upcoming_booking)" do
        result = call
        expect(result).to be_success.and(have_attributes(value!: :no_upcoming_booking))
      end

      it "does not create a MessageLog" do
        expect { call }.not_to change(MessageLog, :count)
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

    context "when an unexpected error is raised" do
      before { allow(Customer).to receive(:find_by).and_raise(StandardError, "db exploded") }

      it "returns Failure(:processing_error)" do
        result = call
        expect(result).to be_failure.and(have_attributes(failure: :processing_error))
      end
    end
  end
end
