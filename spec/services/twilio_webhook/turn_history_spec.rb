# frozen_string_literal: true

require "rails_helper"

RSpec.describe TwilioWebhook::TurnHistory do
  let(:account)  { create(:account) }
  let(:customer) { create(:customer, account: account) }

  describe ".for" do
    context "when customer is nil" do
      it "returns an empty array" do
        expect(described_class.for(account: account, customer: nil)).to eq([])
      end
    end

    context "with no message logs" do
      it "returns an empty array" do
        expect(described_class.for(account: account, customer: customer)).to eq([])
      end
    end

    context "with recent inbound and outbound logs" do
      before do
        create(:message_log, account: account, customer: customer,
               channel: "whatsapp", direction: "inbound",
               body: "quiero un corte", created_at: 10.minutes.ago)
        create(:message_log, account: account, customer: customer,
               channel: "whatsapp", direction: "outbound",
               body: "¿Para cuándo quieres?", created_at: 9.minutes.ago)
      end

      it "returns turns in oldest-first order" do
        turns = described_class.for(account: account, customer: customer)
        expect(turns.map { |t| t[:role] }).to eq(%w[user assistant])
      end

      it "assigns 'user' to inbound and 'assistant' to outbound" do
        turns = described_class.for(account: account, customer: customer)
        expect(turns.find { |t| t[:role] == "user" }[:body]).to eq("quiero un corte")
        expect(turns.find { |t| t[:role] == "assistant" }[:body]).to eq("¿Para cuándo quieres?")
      end
    end

    context "with logs older than WINDOW_DAYS" do
      before do
        create(:message_log, account: account, customer: customer,
               channel: "whatsapp", direction: "inbound",
               body: "mensaje viejo", created_at: (TwilioWebhook::TurnHistory::WINDOW_DAYS + 1).days.ago)
      end

      it "excludes old logs" do
        turns = described_class.for(account: account, customer: customer)
        expect(turns).to be_empty
      end
    end

    context "with logs from a different channel (email)" do
      before do
        create(:message_log, account: account, customer: customer,
               channel: "email", direction: "inbound",
               body: "mensaje por email", created_at: 5.minutes.ago)
      end

      it "excludes non-whatsapp logs" do
        turns = described_class.for(account: account, customer: customer)
        expect(turns).to be_empty
      end
    end

    context "when total character count exceeds TOTAL_CAP" do
      # Each body is 300 chars → truncated to BODY_TRUNCATION (280).
      # Three turns × 280 = 840 > TOTAL_CAP (800), so the oldest is dropped.
      let(:body_a) { "AAA#{" " * 300}" }  # distinctive prefix, long enough to truncate
      let(:body_b) { "B" * 300 }
      let(:body_c) { "C" * 300 }

      before do
        create(:message_log, account: account, customer: customer,
               channel: "whatsapp", direction: "inbound",
               body: body_a, created_at: 30.minutes.ago)
        create(:message_log, account: account, customer: customer,
               channel: "whatsapp", direction: "inbound",
               body: body_b, created_at: 20.minutes.ago)
        create(:message_log, account: account, customer: customer,
               channel: "whatsapp", direction: "inbound",
               body: body_c, created_at: 10.minutes.ago)
      end

      it "drops oldest turns to stay within the cap" do
        turns = described_class.for(account: account, customer: customer)
        bodies = turns.map { |t| t[:body] }
        # body_a (oldest) should be dropped; body_b and body_c kept
        expect(bodies.none? { |b| b.start_with?("AAA") }).to be true
      end
    end

    context "when the customer has past completed bookings" do
      let(:user)    { create(:user, account: account) }
      let(:service) { create(:service, account: account, name: "Corte clásico") }

      before do
        create(:booking, account: account, customer: customer, user: user,
               service: service, status: "completed",
               starts_at: Time.zone.parse("2026-04-02 11:00"))
      end

      it "appends a context entry with past booking info" do
        turns = described_class.for(account: account, customer: customer)
        ctx = turns.find { |t| t[:role] == "context" }
        expect(ctx).to be_present
        expect(ctx[:body]).to include("2026-04-02")
        expect(ctx[:body]).to include("Corte clásico")
      end
    end

    context "when the customer has no completed bookings" do
      it "does not append a context entry" do
        turns = described_class.for(account: account, customer: customer)
        expect(turns.none? { |t| t[:role] == "context" }).to be true
      end
    end

    context "with logs from another account's customer" do
      let(:other_account)  { create(:account) }
      let(:other_customer) { create(:customer, account: other_account) }

      before do
        create(:message_log, account: other_account, customer: other_customer,
               channel: "whatsapp", direction: "inbound",
               body: "mensaje de otro cliente", created_at: 5.minutes.ago)
      end

      it "does not include other accounts' logs" do
        turns = described_class.for(account: account, customer: customer)
        expect(turns).to be_empty
      end
    end
  end
end
