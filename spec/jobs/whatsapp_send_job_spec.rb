require "rails_helper"

RSpec.describe WhatsappSendJob, type: :job do
  let(:account)  { create(:account, plan: "free", whatsapp_quota_used: 0) }
  let(:owner)    { create(:user, account: account, role: "owner") }
  let(:customer) { create(:customer, account: account, phone: "+525551234567") }
  let(:service)  { create(:service, account: account) }
  let(:booking)  { create(:booking, account: account, customer: customer, service: service, user: owner) }

  let(:message_double)  { double("message", sid: "SM123456") }
  let(:messages_double) { double("messages", create: message_double) }
  let(:client_double)   { double("Twilio::REST::Client", messages: messages_double) }

  before do
    ActsAsTenant.test_tenant = account
    allow(Twilio::REST::Client).to receive(:new).and_return(client_double)
  end
  after { ActsAsTenant.test_tenant = nil }

  describe "#perform" do
    context "when booking does not exist" do
      it "returns without error" do
        expect { described_class.perform_now(0, :confirmation) }.not_to raise_error
      end
    end

    context "when quota is exceeded" do
      before { account.update!(whatsapp_quota_used: 100) }

      it "does not call Twilio" do
        described_class.perform_now(booking.id, :confirmation)
        expect(Twilio::REST::Client).not_to have_received(:new)
      end

      it "does not create a MessageLog" do
        expect { described_class.perform_now(booking.id, :confirmation) }
          .not_to change(MessageLog, :count)
      end
    end

    context "when sending a :confirmation message" do
      it "calls Twilio with the customer's number and name in the body" do
        described_class.perform_now(booking.id, :confirmation)
        expect(messages_double).to have_received(:create).with(
          hash_including(
            to:   "whatsapp:#{customer.phone}",
            body: a_string_including(customer.name)
          )
        )
      end

      it "creates an outbound sent MessageLog with Twilio SID" do
        expect { described_class.perform_now(booking.id, :confirmation) }
          .to change(MessageLog, :count).by(1)
        log = MessageLog.last
        expect(log.direction).to eq("outbound")
        expect(log.status).to eq("sent")
        expect(log.external_id).to eq("SM123456")
        expect(log.channel).to eq("whatsapp")
      end

      it "increments whatsapp_quota_used" do
        expect { described_class.perform_now(booking.id, :confirmation) }
          .to change { account.reload.whatsapp_quota_used }.by(1)
      end
    end

    context "when sending a :'24h' message" do
      it "includes confirm/cancel instructions" do
        described_class.perform_now(booking.id, :"24h")
        expect(messages_double).to have_received(:create).with(
          hash_including(body: a_string_including("1"))
        )
      end
    end

    context "when sending a :'2h' message" do
      it "mentions 2 horas" do
        described_class.perform_now(booking.id, :"2h")
        expect(messages_double).to have_received(:create).with(
          hash_including(body: a_string_including("2 horas"))
        )
      end
    end

    context "when Twilio raises an error" do
      before do
        allow(messages_double).to receive(:create)
          .and_raise(Twilio::REST::TwilioError, "connection error")
      end

      it "creates a failed MessageLog without external_id" do
        described_class.perform_now(booking.id, :confirmation) rescue nil
        log = MessageLog.last
        expect(log.status).to eq("failed")
        expect(log.external_id).to be_nil
      end

      it "re-raises the error" do
        expect { described_class.perform_now(booking.id, :confirmation) }
          .to raise_error(Twilio::REST::TwilioError)
      end

      it "does not increment quota" do
        expect { described_class.perform_now(booking.id, :confirmation) rescue nil }
          .not_to change { account.reload.whatsapp_quota_used }
      end
    end
  end
end
