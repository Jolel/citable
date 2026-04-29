# frozen_string_literal: true

require "rails_helper"

RSpec.describe Llm::NluParser do
  let(:account) { build_stubbed(:account) }

  def stub_client(content:, input_tokens: 100, output_tokens: 20)
    allow(Llm::Client).to receive(:call).and_return(
      content: content, input_tokens: input_tokens, output_tokens: output_tokens, model: Llm::Client::DEFAULT_MODEL
    )
  end

  describe ".parse_datetime" do
    around { |ex| travel_to(Time.zone.parse("2026-04-26 10:00:00"), &ex) }

    context "when the LLM returns a high-confidence datetime" do
      before { stub_client(content: { "starts_at" => "2026-05-02T15:00:00", "confidence" => 0.95 }) }

      it "returns a Result with the parsed Time" do
        result = described_class.parse_datetime("viernes a las 3", account: account)

        expect(result).to be_a(Llm::NluParser::Result)
        expect(result.value).to eq(Time.zone.parse("2026-05-02T15:00:00"))
      end

      it "returns token usage from the LLM call" do
        result = described_class.parse_datetime("viernes a las 3", account: account)

        expect(result.input_tokens).to eq(100)
        expect(result.output_tokens).to eq(20)
        expect(result.model).to eq(Llm::Client::DEFAULT_MODEL)
      end
    end

    context "when the LLM returns a low-confidence result" do
      before { stub_client(content: { "starts_at" => "2026-05-02T15:00:00", "confidence" => 0.5 }) }

      it "returns nil" do
        expect(described_class.parse_datetime("who knows", account: account)).to be_nil
      end
    end

    context "when the LLM returns null starts_at" do
      before { stub_client(content: { "starts_at" => nil, "confidence" => 0.9 }) }

      it "returns nil" do
        expect(described_class.parse_datetime("hola", account: account)).to be_nil
      end
    end

    context "when the LLM call raises an error" do
      before { allow(Llm::Client).to receive(:call).and_raise(Llm::Client::Error, "timeout") }

      it "returns nil without raising" do
        expect(described_class.parse_datetime("viernes a las 3", account: account)).to be_nil
      end
    end
  end

  describe ".parse_service" do
    let(:services) do
      [
        instance_double("Service", name: "Corte de cabello"),
        instance_double("Service", name: "Tinte"),
        instance_double("Service", name: "Manicura")
      ]
    end

    context "when the LLM returns a high-confidence match" do
      before { stub_client(content: { "service_index" => 1, "confidence" => 0.92 }) }

      it "returns the matched service" do
        result = described_class.parse_service("quiero cortarme el pelo", services, account: account)

        expect(result).to be_a(Llm::NluParser::Result)
        expect(result.value).to eq(services[0])
      end
    end

    context "when the LLM returns a low-confidence match" do
      before { stub_client(content: { "service_index" => 2, "confidence" => 0.6 }) }

      it "returns nil" do
        expect(described_class.parse_service("algo", services, account: account)).to be_nil
      end
    end

    context "when the LLM returns null index" do
      before { stub_client(content: { "service_index" => nil, "confidence" => 0.9 }) }

      it "returns nil" do
        expect(described_class.parse_service("hola", services, account: account)).to be_nil
      end
    end

    context "when the LLM returns an out-of-range index" do
      before { stub_client(content: { "service_index" => 99, "confidence" => 0.95 }) }

      it "returns nil" do
        expect(described_class.parse_service("algo", services, account: account)).to be_nil
      end
    end

    context "when services list is empty" do
      it "returns nil without calling the LLM" do
        expect(Llm::Client).not_to receive(:call)
        expect(described_class.parse_service("algo", [], account: account)).to be_nil
      end
    end

    context "when the LLM call raises an error" do
      before { allow(Llm::Client).to receive(:call).and_raise(Llm::Client::Error, "network error") }

      it "returns nil without raising" do
        expect(described_class.parse_service("algo", services, account: account)).to be_nil
      end
    end
  end
end
