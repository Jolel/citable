# frozen_string_literal: true

require "rails_helper"

RSpec.describe Llm::GreetingGenerator do
  def stub_client(message:, input_tokens: 80, output_tokens: 20)
    allow(Llm::Client).to receive(:call).and_return(
      content:       { "message" => message },
      input_tokens:  input_tokens,
      output_tokens: output_tokens,
      model:         Llm::Client::DEFAULT_MODEL
    )
  end

  let(:account)  { create(:account, name: "Estudio de Ana") }
  let(:customer) { create(:customer, account: account, name: "María") }

  before { create(:service, account: account, name: "Corte de cabello") }

  describe ".call" do
    context "when the LLM returns a greeting intro" do
      # GreetingGenerator returns ONLY the intro sentence(s) — no service list.
      # StartConversation is responsible for appending the list.
      before { stub_client(message: "¡Hola, María! ¿Qué tal?") }

      it "returns a Result with the LLM message" do
        result = described_class.call(account: account, customer: customer)

        expect(result).to be_a(Llm::GreetingGenerator::Result)
        expect(result.message).to eq("¡Hola, María! ¿Qué tal?")
      end

      it "includes token usage metadata" do
        result = described_class.call(account: account, customer: customer)

        expect(result.input_tokens).to eq(80)
        expect(result.output_tokens).to eq(20)
        expect(result.model).to eq(Llm::Client::DEFAULT_MODEL)
      end

      it "passes the account name in the system prompt" do
        described_class.call(account: account, customer: customer)

        expect(Llm::Client).to have_received(:call).with(
          hash_including(system: include("Estudio de Ana"))
        )
      end

      it "tells the LLM not to include the service list" do
        described_class.call(account: account, customer: customer)

        expect(Llm::Client).to have_received(:call).with(
          hash_including(user: include("automáticamente"))
        )
      end

      it "passes the customer name in the user prompt" do
        described_class.call(account: account, customer: customer)

        expect(Llm::Client).to have_received(:call).with(
          hash_including(user: include("María"))
        )
      end
    end

    context "when customer is nil (new customer)" do
      before { stub_client(message: "¡Hola! Bienvenid@ a Estudio de Ana. ¿Cómo te llamas?") }

      it "returns a greeting that asks for the name" do
        result = described_class.call(account: account, customer: nil)

        expect(result.message).to be_present
      end

      it "references 'cliente nuevo' in the user prompt" do
        described_class.call(account: account, customer: nil)

        expect(Llm::Client).to have_received(:call).with(
          hash_including(user: include("cliente nuevo"))
        )
      end
    end

    context "when the LLM returns a blank message" do
      before { stub_client(message: "") }

      it "returns nil" do
        expect(described_class.call(account: account, customer: customer)).to be_nil
      end
    end

    context "when the LLM call raises an error" do
      before { allow(Llm::Client).to receive(:call).and_raise(Llm::Client::Error, "timeout") }

      it "returns nil without raising" do
        expect(described_class.call(account: account, customer: customer)).to be_nil
      end
    end
  end
end
