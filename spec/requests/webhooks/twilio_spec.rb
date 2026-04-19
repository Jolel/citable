require "rails_helper"

RSpec.describe "POST /webhooks/twilio", type: :request do
  let(:account)  { create(:account) }
  let(:owner)    { create(:user, account: account, role: "owner") }
  let(:customer) { create(:customer, account: account, phone: "+525551234567") }
  let(:service)  { create(:service, account: account) }
  let(:booking) do
    create(:booking, account: account, customer: customer,
           service: service, user: owner, status: "pending")
  end

  before do
    booking
    allow_any_instance_of(Twilio::Security::RequestValidator)
      .to receive(:validate).and_return(true)
  end

  context "with invalid Twilio signature" do
    before do
      allow_any_instance_of(Twilio::Security::RequestValidator)
        .to receive(:validate).and_return(false)
    end

    it "returns 403" do
      post "/webhooks/twilio", params: { From: "whatsapp:+525551234567", Body: "1" }
      expect(response).to have_http_status(:forbidden)
    end

    it "does not change booking status" do
      expect { post "/webhooks/twilio", params: { From: "whatsapp:+525551234567", Body: "1" } }
        .not_to change { booking.reload.status }
    end
  end

  context "with valid Twilio signature" do
    context "when customer replies '1'" do
      it "returns 200" do
        post "/webhooks/twilio", params: { From: "whatsapp:+525551234567", Body: "1" }
        expect(response).to have_http_status(:ok)
      end

      it "confirms the booking" do
        post "/webhooks/twilio", params: { From: "whatsapp:+525551234567", Body: "1" }
        expect(booking.reload.status).to eq("confirmed")
      end

      it "creates an inbound whatsapp MessageLog" do
        expect { post "/webhooks/twilio", params: { From: "whatsapp:+525551234567", Body: "1" } }
          .to change(MessageLog, :count).by(1)
        log = MessageLog.last
        expect(log.direction).to eq("inbound")
        expect(log.channel).to eq("whatsapp")
        expect(log.body).to eq("1")
        expect(log.status).to eq("delivered")
      end
    end

    context "when customer replies '2'" do
      it "cancels the booking and returns 200" do
        post "/webhooks/twilio", params: { From: "whatsapp:+525551234567", Body: "2" }
        expect(response).to have_http_status(:ok)
        expect(booking.reload.status).to eq("cancelled")
      end
    end

    context "when customer sends an unrecognized reply" do
      it "returns 200 and does not change booking" do
        post "/webhooks/twilio", params: { From: "whatsapp:+525551234567", Body: "gracias" }
        expect(response).to have_http_status(:ok)
        expect(booking.reload.status).to eq("pending")
      end
    end

    context "when customer phone is not found" do
      it "returns 200 without error" do
        post "/webhooks/twilio", params: { From: "whatsapp:+529999999999", Body: "1" }
        expect(response).to have_http_status(:ok)
      end

      it "does not create a MessageLog" do
        expect { post "/webhooks/twilio", params: { From: "whatsapp:+529999999999", Body: "1" } }
          .not_to change(MessageLog, :count)
      end
    end

    context "when customer has no upcoming active booking" do
      before { booking.update!(status: "completed") }

      it "returns 200 without error" do
        post "/webhooks/twilio", params: { From: "whatsapp:+525551234567", Body: "1" }
        expect(response).to have_http_status(:ok)
      end
    end
  end
end
