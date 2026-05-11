# frozen_string_literal: true

require "rails_helper"

RSpec.describe TwilioWebhook::AiUsageRecorder do
  let(:account)  { create(:account) }
  let(:customer) { create(:customer, account: account) }

  describe ".record" do
    context "when there is a recent inbound MessageLog" do
      let!(:log) do
        create(:message_log, account: account, customer: customer,
               channel: "whatsapp", direction: "inbound", body: "hola", status: "delivered")
      end

      let(:hash) do
        { input_tokens: 150, output_tokens: 25, model: "gemini-2.5-pro" }
      end

      it "stamps token usage onto the most recent inbound log" do
        described_class.record(account: account, hash: hash)

        log.reload
        expect(log.ai_input_tokens).to eq(150)
        expect(log.ai_output_tokens).to eq(25)
        expect(log.ai_model).to eq("gemini-2.5-pro")
      end

      it "updates the most recent log (not an older one)" do
        older = create(:message_log, account: account, customer: customer,
                       channel: "whatsapp", direction: "inbound",
                       body: "anterior", status: "delivered",
                       created_at: 2.minutes.ago)

        described_class.record(account: account, hash: hash)

        expect(log.reload.ai_input_tokens).to eq(150)
        expect(older.reload.ai_input_tokens).to be_nil
      end
    end

    context "when there are no inbound logs for the account" do
      it "does not raise" do
        expect do
          described_class.record(
            account: account,
            hash:    { input_tokens: 50, output_tokens: 10, model: "test" }
          )
        end.not_to raise_error
      end
    end

    context "when hash is nil" do
      it "does not raise" do
        expect { described_class.record(account: account, hash: nil) }.not_to raise_error
      end
    end
  end
end
