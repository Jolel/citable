# frozen_string_literal: true

require "rails_helper"

RSpec.describe Llm::NluParser do
  let(:llm) { instance_double(Llm::Port) }

  def stub_llm(content:, input_tokens: 100, output_tokens: 20)
    allow(llm).to receive(:call).and_return(
      Llm::Response.new(content: content, input_tokens: input_tokens,
                        output_tokens: output_tokens, model: "test-model")
    )
  end

  describe ".parse_datetime" do
    around { |ex| travel_to(Time.zone.parse("2026-04-26 10:00:00"), &ex) }

    context "when the LLM returns a high-confidence datetime" do
      before { stub_llm(content: { "starts_at" => "2026-05-02T15:00:00", "confidence" => 0.95 }) }

      it "returns Success with the parsed Time" do
        result = described_class.parse_datetime("viernes a las 3", llm: llm)

        expect(result).to be_success
        expect(result.value![:value]).to eq(Time.zone.parse("2026-05-02T15:00:00"))
      end

      it "includes token usage in the Success hash" do
        result = described_class.parse_datetime("viernes a las 3", llm: llm)

        expect(result.value![:input_tokens]).to eq(100)
        expect(result.value![:output_tokens]).to eq(20)
        expect(result.value![:model]).to eq("test-model")
      end
    end

    context "when the LLM returns a low-confidence result" do
      before { stub_llm(content: { "starts_at" => "2026-05-02T15:00:00", "confidence" => 0.5 }) }

      it "returns Failure(:low_confidence)" do
        result = described_class.parse_datetime("who knows", llm: llm)

        expect(result).to be_failure
        expect(result.failure).to eq(:low_confidence)
      end
    end

    context "when the LLM returns null starts_at" do
      before { stub_llm(content: { "starts_at" => nil, "confidence" => 0.9 }) }

      it "returns Failure(:low_confidence)" do
        expect(described_class.parse_datetime("hola", llm: llm)).to be_failure
      end
    end

    context "when the LLM raises an error" do
      before { allow(llm).to receive(:call).and_raise(Llm::Port::Error, "timeout") }

      it "returns Failure(:llm_error)" do
        result = described_class.parse_datetime("viernes a las 3", llm: llm)

        expect(result).to be_failure
        expect(result.failure).to eq(:llm_error)
      end
    end

    context "when the LLM returns an ISO string with a timezone offset" do
      # The LLM occasionally emits offsets like -05:00 (treating CDMX as US Central
      # with DST). Mexico_City is UTC-6 year-round; we strip the offset and
      # interpret the wall-clock time as local.
      before { stub_llm(content: { "starts_at" => "2026-05-03T17:00:00-05:00", "confidence" => 0.95 }) }

      it "interprets the wall-clock time as Mexico_City local (not converted)" do
        result = described_class.parse_datetime("pasado mañana a las 5 pm", llm: llm)

        expect(result).to be_success
        time = result.value![:value]
        expect(time.in_time_zone("America/Mexico_City").strftime("%Y-%m-%d %H:%M")).to eq("2026-05-03 17:00")
      end
    end

    context "when the LLM returns an ISO string with a Z (UTC) suffix" do
      before { stub_llm(content: { "starts_at" => "2026-05-03T17:00:00Z", "confidence" => 0.95 }) }

      it "still interprets the wall-clock time as Mexico_City local" do
        result = described_class.parse_datetime("pasado mañana a las 5 pm", llm: llm)

        expect(result).to be_success
        expect(result.value![:value].in_time_zone("America/Mexico_City").strftime("%Y-%m-%d %H:%M"))
          .to eq("2026-05-03 17:00")
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
      before { stub_llm(content: { "service_index" => 1, "confidence" => 0.92 }) }

      it "returns Success with the matched service" do
        result = described_class.parse_service("quiero cortarme el pelo", services, llm: llm)

        expect(result).to be_success
        expect(result.value![:value]).to eq(services[0])
      end
    end

    context "when the LLM returns a low-confidence match" do
      before { stub_llm(content: { "service_index" => 2, "confidence" => 0.6 }) }

      it "returns Failure(:low_confidence)" do
        expect(described_class.parse_service("algo", services, llm: llm)).to be_failure
      end
    end

    context "when the LLM returns null index" do
      before { stub_llm(content: { "service_index" => nil, "confidence" => 0.9 }) }

      it "returns Failure(:low_confidence)" do
        expect(described_class.parse_service("hola", services, llm: llm)).to be_failure
      end
    end

    context "when the LLM returns an out-of-range index" do
      before { stub_llm(content: { "service_index" => 99, "confidence" => 0.95 }) }

      it "returns Failure(:low_confidence)" do
        expect(described_class.parse_service("algo", services, llm: llm)).to be_failure
      end
    end

    context "when services list is empty" do
      it "returns Failure without calling the LLM" do
        expect(llm).not_to receive(:call)
        expect(described_class.parse_service("algo", [], llm: llm)).to be_failure
      end
    end

    context "when the LLM raises an error" do
      before { allow(llm).to receive(:call).and_raise(Llm::Port::Error, "network error") }

      it "returns Failure(:llm_error)" do
        result = described_class.parse_service("algo", services, llm: llm)

        expect(result.failure).to eq(:llm_error)
      end
    end
  end

  describe ".parse_confirmation" do
    context "when the LLM returns high-confidence 'confirmed'" do
      before { stub_llm(content: { "decision" => "confirmed", "confidence" => 0.97 }) }

      it "returns Success with value :confirmed" do
        result = described_class.parse_confirmation("dale", llm: llm)

        expect(result).to be_success
        expect(result.value![:value]).to eq(:confirmed)
      end

      it "includes token usage in the Success hash" do
        result = described_class.parse_confirmation("claro que sí", llm: llm)

        expect(result.value![:input_tokens]).to eq(100)
        expect(result.value![:output_tokens]).to eq(20)
      end
    end

    context "when the LLM returns high-confidence 'cancelled'" do
      before { stub_llm(content: { "decision" => "cancelled", "confidence" => 0.91 }) }

      it "returns Success with value :cancelled" do
        result = described_class.parse_confirmation("mejor no", llm: llm)

        expect(result.value![:value]).to eq(:cancelled)
      end
    end

    context "when the LLM returns low confidence" do
      before { stub_llm(content: { "decision" => "confirmed", "confidence" => 0.5 }) }

      it "returns Failure(:low_confidence)" do
        expect(described_class.parse_confirmation("quizás", llm: llm)).to be_failure
      end
    end

    context "when the LLM returns null decision" do
      before { stub_llm(content: { "decision" => nil, "confidence" => 0.9 }) }

      it "returns Failure(:low_confidence)" do
        expect(described_class.parse_confirmation("???", llm: llm)).to be_failure
      end
    end

    context "when the LLM raises an error" do
      before { allow(llm).to receive(:call).and_raise(Llm::Port::Error, "timeout") }

      it "returns Failure(:llm_error)" do
        result = described_class.parse_confirmation("dale", llm: llm)

        expect(result.failure).to eq(:llm_error)
      end
    end
  end
end
