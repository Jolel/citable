# frozen_string_literal: true

require "rails_helper"

RSpec.describe Llm::QuestionClassifier do
  let(:account) { build_stubbed(:account) }
  let(:services) do
    [
      instance_double("Service", name: "Corte de cabello"),
      instance_double("Service", name: "Tinte")
    ]
  end
  let(:llm) { instance_double(Llm::Port) }

  def stub_llm(content:, input_tokens: 50, output_tokens: 10)
    allow(llm).to receive(:call).and_return(
      Llm::Response.new(content: content, input_tokens: input_tokens,
                        output_tokens: output_tokens, model: "test-model")
    )
  end

  context "with a high-confidence services_list intent" do
    before { stub_llm(content: { "intent" => "services_list", "service_index" => nil, "confidence" => 0.95 }) }

    it "returns Success with intent :services_list and nil service" do
      result = described_class.call("¿qué servicios tienen?", services: services, account: account, llm: llm)

      expect(result).to be_success
      expect(result.value![:intent]).to eq(:services_list)
      expect(result.value![:service]).to be_nil
      expect(result.value![:input_tokens]).to eq(50)
    end
  end

  context "with a high-confidence price intent referencing a service" do
    before { stub_llm(content: { "intent" => "price", "service_index" => 1, "confidence" => 0.92 }) }

    it "returns Success with the referenced service" do
      result = described_class.call("¿cuánto cuesta el corte?", services: services, account: account, llm: llm)

      expect(result.value![:intent]).to eq(:price)
      expect(result.value![:service]).to eq(services[0])
    end
  end

  context "with a price intent and no service mentioned" do
    before { stub_llm(content: { "intent" => "price", "service_index" => nil, "confidence" => 0.9 }) }

    it "returns Success with nil service" do
      result = described_class.call("¿cuánto cuestan?", services: services, account: account, llm: llm)

      expect(result.value![:service]).to be_nil
    end
  end

  context "with a high-confidence hours intent" do
    before { stub_llm(content: { "intent" => "hours", "service_index" => nil, "confidence" => 0.88 }) }

    it "returns Success with intent :hours" do
      result = described_class.call("¿a qué hora abren?", services: services, account: account, llm: llm)

      expect(result.value![:intent]).to eq(:hours)
    end
  end

  context "with intent 'booking'" do
    before { stub_llm(content: { "intent" => "booking", "service_index" => 1, "confidence" => 0.95 }) }

    it "returns Success with intent :booking (caller decides if it's actionable)" do
      result = described_class.call("quiero un corte mañana", services: services, account: account, llm: llm)

      expect(result).to be_success
      expect(result.value![:intent]).to eq(:booking)
      expect(result.value![:service]).to eq(services[0])
    end
  end

  context "with intent 'cancel'" do
    before { stub_llm(content: { "intent" => "cancel", "service_index" => nil, "confidence" => 0.93 }) }

    it "returns Success with intent :cancel" do
      result = described_class.call("quiero cancelar mi cita", services: services, account: account, llm: llm)

      expect(result).to be_success
      expect(result.value![:intent]).to eq(:cancel)
    end
  end

  context "with intent 'other'" do
    before { stub_llm(content: { "intent" => "other", "service_index" => nil, "confidence" => 0.9 }) }

    it "returns Failure(:not_a_question)" do
      expect(described_class.call("hola", services: services, account: account, llm: llm)).to be_failure
    end
  end

  context "with intent 'greeting'" do
    before { stub_llm(content: { "intent" => "greeting", "service_index" => nil, "confidence" => 0.95 }) }

    it "returns Failure(:not_a_question) so callers fall through to greeting handling" do
      expect(described_class.call("hola", services: services, account: account, llm: llm)).to be_failure
    end
  end

  context "with intent 'address'" do
    before { stub_llm(content: { "intent" => "address", "service_index" => nil, "confidence" => 0.9 }) }

    it "returns Success with intent :address" do
      result = described_class.call("¿cuál es la dirección?", services: services, account: account, llm: llm)
      expect(result.value![:intent]).to eq(:address)
    end
  end

  context "with intent 'appointment_date'" do
    before { stub_llm(content: { "intent" => "appointment_date", "service_index" => nil, "confidence" => 0.9 }) }

    it "returns Success with intent :appointment_date" do
      result = described_class.call("¿cuándo es mi cita?", services: services, account: account, llm: llm)
      expect(result.value![:intent]).to eq(:appointment_date)
    end
  end

  context "with intent 'list_appointments'" do
    before { stub_llm(content: { "intent" => "list_appointments", "service_index" => nil, "confidence" => 0.9 }) }

    it "returns Success with intent :list_appointments" do
      result = described_class.call("tengo citas", services: services, account: account, llm: llm)
      expect(result.value![:intent]).to eq(:list_appointments)
    end
  end

  context "with confidence just under MIN_CONFIDENCE (0.65)" do
    before { stub_llm(content: { "intent" => "price", "service_index" => 1, "confidence" => 0.6 }) }

    it "returns Failure(:not_a_question)" do
      expect(described_class.call("algo", services: services, account: account, llm: llm)).to be_failure
    end
  end

  context "with confidence just over the new lower threshold (0.7)" do
    before { stub_llm(content: { "intent" => "price", "service_index" => 1, "confidence" => 0.7 }) }

    it "returns Success — lowered threshold accepts borderline questions" do
      result = described_class.call("cuánto", services: services, account: account, llm: llm)
      expect(result).to be_success
      expect(result.value![:intent]).to eq(:price)
    end
  end

  context "when the LLM raises an error" do
    before { allow(llm).to receive(:call).and_raise(Llm::Port::Error, "timeout") }

    it "returns Failure(:llm_error)" do
      result = described_class.call("¿qué hacen?", services: services, account: account, llm: llm)

      expect(result.failure).to eq(:llm_error)
    end
  end

  context "with no services" do
    before { stub_llm(content: { "intent" => "services_list", "service_index" => nil, "confidence" => 0.95 }) }

    it "still classifies (uses placeholder list)" do
      result = described_class.call("¿qué servicios?", services: [], account: account, llm: llm)

      expect(result.value![:intent]).to eq(:services_list)
    end
  end
end
