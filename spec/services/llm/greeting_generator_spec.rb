# frozen_string_literal: true

require "rails_helper"

RSpec.describe Llm::GreetingGenerator do
  let(:llm) { instance_double(Llm::Port) }

  def stub_llm(message:, input_tokens: 80, output_tokens: 20)
    allow(llm).to receive(:call).and_return(
      Llm::Response.new(content: { "message" => message }, input_tokens: input_tokens,
                        output_tokens: output_tokens, model: "test-model")
    )
  end

  let(:account)  { create(:account, name: "Estudio de Ana") }
  let(:customer) { create(:customer, account: account, name: "María") }

  before { create(:service, account: account, name: "Corte de cabello") }

  describe ".call" do
    context "when the LLM returns a greeting intro" do
      before { stub_llm(message: "¡Hola, María! ¿Qué tal?") }

      it "returns Success with the LLM message" do
        result = described_class.call(account: account, customer: customer, llm: llm)

        expect(result).to be_success
        expect(result.value![:message]).to eq("¡Hola, María! ¿Qué tal?")
      end

      it "includes token usage in the Success hash" do
        result = described_class.call(account: account, customer: customer, llm: llm)

        expect(result.value![:input_tokens]).to eq(80)
        expect(result.value![:output_tokens]).to eq(20)
        expect(result.value![:model]).to eq("test-model")
      end

      it "passes the account name in the system prompt" do
        described_class.call(account: account, customer: customer, llm: llm)

        expect(llm).to have_received(:call).with(hash_including(system: include("Estudio de Ana")))
      end

      it "tells the LLM not to include the service list" do
        described_class.call(account: account, customer: customer, llm: llm)

        expect(llm).to have_received(:call).with(hash_including(user: include("automáticamente")))
      end

      it "passes the customer name in the user prompt" do
        described_class.call(account: account, customer: customer, llm: llm)

        expect(llm).to have_received(:call).with(hash_including(user: include("María")))
      end
    end

    context "when customer is nil (new customer)" do
      before { stub_llm(message: "¡Hola! Bienvenid@ a Estudio de Ana. ¿Cómo te llamas?") }

      it "returns Success with a greeting" do
        result = described_class.call(account: account, customer: nil, llm: llm)

        expect(result).to be_success
        expect(result.value![:message]).to be_present
      end

      it "references 'cliente nuevo' in the user prompt" do
        described_class.call(account: account, customer: nil, llm: llm)

        expect(llm).to have_received(:call).with(hash_including(user: include("cliente nuevo")))
      end
    end

    context "when the LLM returns a blank message" do
      before { stub_llm(message: "") }

      it "returns Failure(:blank_message)" do
        result = described_class.call(account: account, customer: customer, llm: llm)

        expect(result).to be_failure
        expect(result.failure).to eq(:blank_message)
      end
    end

    context "when the LLM raises an error" do
      before { allow(llm).to receive(:call).and_raise(Llm::Port::Error, "timeout") }

      it "returns Failure(:llm_error)" do
        result = described_class.call(account: account, customer: customer, llm: llm)

        expect(result).to be_failure
        expect(result.failure).to eq(:llm_error)
      end
    end
  end
end
