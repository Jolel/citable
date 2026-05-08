# frozen_string_literal: true

require "rails_helper"

RSpec.describe TwilioWebhook::Disambiguator do
  let(:account)      { create(:account) }
  let(:conversation) { create(:whatsapp_conversation, account: account, step: "awaiting_service") }

  describe ".call with slot: :service" do
    let(:service_a) { create(:service, account: account, name: "Corte clásico") }
    let(:service_b) { create(:service, account: account, name: "Corte fade") }

    subject(:result) { described_class.call(slot: :service, candidates: [ service_a, service_b ], conversation: conversation) }

    it "returns a message listing the candidates with numbers" do
      expect(result[:message]).to include("1. *Corte clásico*")
      expect(result[:message]).to include("2. *Corte fade*")
    end

    it "includes a prompt to choose by number or name" do
      expect(result[:message]).to match(/escribe/i)
    end

    it "returns metadata with slot and candidate ids" do
      expect(result[:metadata]).to eq(
        "slot"       => "service",
        "candidates" => [ service_a.id, service_b.id ]
      )
    end

    context "with a single candidate" do
      subject(:result) { described_class.call(slot: :service, candidates: [ service_a ], conversation: conversation) }

      it "lists only that candidate" do
        expect(result[:message]).to include("1. *Corte clásico*")
        expect(result[:message]).not_to include("2.")
      end

      it "returns metadata with one id" do
        expect(result[:metadata]["candidates"]).to eq([ service_a.id ])
      end
    end
  end
end
