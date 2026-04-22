# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Webhooks::Twilio", type: :request do
  before do
    allow(GoogleCalendarSyncJob).to receive(:perform_later)
    allow(ReminderJob).to receive(:set).and_return(double(perform_later: true))
    allow_any_instance_of(Twilio::Security::RequestValidator)
      .to receive(:validate).and_return(true)
  end

  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:service) { create(:service, account: account) }
  let(:customer) { create(:customer, account: account, phone: "+5215512345678") }
  let!(:booking) do
    create(:booking, account: account, customer: customer, user: user, service: service,
           starts_at: 2.days.from_now, status: "pending")
  end

  def post_twilio(from:, body:)
    post webhooks_twilio_path, params: { From: from, Body: body }
  end

  describe "POST /webhooks/twilio" do
    context "with invalid Twilio signature" do
      before do
        allow_any_instance_of(Twilio::Security::RequestValidator)
          .to receive(:validate).and_return(false)
      end

      it "returns 403" do
        post_twilio(from: "whatsapp:+5215512345678", body: "1")
        expect(response).to have_http_status(:forbidden)
      end

      it "does not change booking status" do
        expect { post_twilio(from: "whatsapp:+5215512345678", body: "1") }
          .not_to change { booking.reload.status }
      end
    end

    it "returns 200 OK" do
      post_twilio(from: "whatsapp:+5215512345678", body: "1")
      expect(response).to have_http_status(:ok)
    end

    context "when customer replies '1'" do
      it "confirms the booking" do
        post_twilio(from: "whatsapp:+5215512345678", body: "1")
        expect(booking.reload).to be_confirmed
      end

      it "creates an inbound MessageLog" do
        expect {
          post_twilio(from: "whatsapp:+5215512345678", body: "1")
        }.to change(MessageLog, :count).by(1)

        log = MessageLog.last
        expect(log.direction).to eq("inbound")
        expect(log.channel).to eq("whatsapp")
        expect(log.body).to eq("1")
        expect(log.status).to eq("delivered")
      end
    end

    context "when customer replies '2'" do
      it "cancels the booking" do
        post_twilio(from: "whatsapp:+5215512345678", body: "2")
        expect(booking.reload).to be_cancelled
      end

      it "creates an inbound MessageLog" do
        expect {
          post_twilio(from: "whatsapp:+5215512345678", body: "2")
        }.to change(MessageLog, :count).by(1)
      end
    end

    context "when customer sends an unrecognized reply" do
      it "does not change booking status" do
        expect {
          post_twilio(from: "whatsapp:+5215512345678", body: "hola")
        }.not_to change { booking.reload.status }
      end

      it "still logs the inbound message" do
        expect {
          post_twilio(from: "whatsapp:+5215512345678", body: "hola")
        }.to change(MessageLog, :count).by(1)
      end
    end

    context "when phone number is not recognized" do
      it "does nothing and returns 200" do
        expect {
          post_twilio(from: "whatsapp:+19990000000", body: "1")
        }.not_to change(MessageLog, :count)
        expect(response).to have_http_status(:ok)
      end
    end

    context "when customer has no upcoming active booking" do
      before { booking.update_columns(starts_at: 2.days.ago, ends_at: 1.day.ago) }

      it "does not create a log or change booking status" do
        expect {
          post_twilio(from: "whatsapp:+5215512345678", body: "1")
        }.not_to change(MessageLog, :count)
      end
    end
  end
end
