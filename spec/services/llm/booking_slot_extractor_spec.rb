# frozen_string_literal: true

require "rails_helper"

RSpec.describe Llm::BookingSlotExtractor do
  let(:llm) { instance_double(Llm::Port) }

  let(:corte)    { instance_double("Service", name: "Corte de cabello") }
  let(:tinte)    { instance_double("Service", name: "Tinte") }
  let(:manicure) { instance_double("Service", name: "Manicure") }
  let(:services) { [ corte, tinte, manicure ] }

  def stub_llm(content:, input_tokens: 120, output_tokens: 30)
    allow(llm).to receive(:call).and_return(
      Llm::Response.new(
        content:       content,
        input_tokens:  input_tokens,
        output_tokens: output_tokens,
        model:         "test-model"
      )
    )
  end

  def empty_confidences
    { "service" => 0.0, "datetime" => 0.0, "address" => 0.0, "confirmation" => 0.0 }
  end

  def call(body = "hola")
    described_class.call(body: body, services: services, llm: llm)
  end

  around { |ex| travel_to(Time.zone.parse("2026-05-07 10:00:00"), &ex) }

  # ── Success shape ────────────────────────────────────────────────────────────

  describe "Success shape" do
    before do
      stub_llm(content: {
        "service_index"     => nil,
        "starts_at"         => nil,
        "address"           => nil,
        "confirmation"      => nil,
        "confidences"       => empty_confidences,
        "service_alternates" => []
      })
    end

    it "returns a Success result" do
      expect(call).to be_success
    end

    it "includes token metadata" do
      result = call
      expect(result.value![:input_tokens]).to eq(120)
      expect(result.value![:output_tokens]).to eq(30)
      expect(result.value![:model]).to eq("test-model")
    end

    it "includes a :slots hash with four keys" do
      slots = call.value![:slots]
      expect(slots.keys).to match_array(%i[service starts_at address confirmation])
    end

    it "includes a :confidences hash" do
      expect(call.value![:confidences]).to be_a(Hash)
    end

    it "includes a :top_candidates array" do
      expect(call.value![:top_candidates]).to be_an(Array)
    end
  end

  # ── Service extraction ───────────────────────────────────────────────────────

  describe "service slot" do
    context "when LLM returns a high-confidence service match" do
      before do
        stub_llm(content: {
          "service_index"     => 1,
          "starts_at"         => nil,
          "address"           => nil,
          "confirmation"      => nil,
          "confidences"       => empty_confidences.merge("service" => 0.92),
          "service_alternates" => []
        })
      end

      it "returns the matched Service object" do
        expect(call.value![:slots][:service]).to eq(corte)
      end
    end

    context "when LLM returns confidence below SERVICE_MIN_CONFIDENCE (0.8)" do
      before do
        stub_llm(content: {
          "service_index"     => 1,
          "starts_at"         => nil,
          "address"           => nil,
          "confirmation"      => nil,
          "confidences"       => empty_confidences.merge("service" => 0.65),
          "service_alternates" => []
        })
      end

      it "returns nil for service" do
        expect(call.value![:slots][:service]).to be_nil
      end
    end

    context "when LLM returns null service_index" do
      before do
        stub_llm(content: {
          "service_index"     => nil,
          "starts_at"         => nil,
          "address"           => nil,
          "confirmation"      => nil,
          "confidences"       => empty_confidences,
          "service_alternates" => []
        })
      end

      it "returns nil for service" do
        expect(call("lo de siempre").value![:slots][:service]).to be_nil
      end
    end

    context "when LLM returns an out-of-range index" do
      before do
        stub_llm(content: {
          "service_index"     => 99,
          "starts_at"         => nil,
          "address"           => nil,
          "confirmation"      => nil,
          "confidences"       => empty_confidences.merge("service" => 0.95),
          "service_alternates" => []
        })
      end

      it "returns nil for service (bounds check)" do
        expect(call.value![:slots][:service]).to be_nil
      end
    end
  end

  # ── Datetime extraction ──────────────────────────────────────────────────────

  describe "starts_at slot" do
    context "when LLM returns a high-confidence datetime" do
      before do
        stub_llm(content: {
          "service_index"     => nil,
          "starts_at"         => "2026-05-09T15:00:00",
          "address"           => nil,
          "confirmation"      => nil,
          "confidences"       => empty_confidences.merge("datetime" => 0.9),
          "service_alternates" => []
        })
      end

      it "returns the parsed Time object" do
        result = call("el viernes a las 3")
        expect(result.value![:slots][:starts_at]).to eq(Time.zone.parse("2026-05-09T15:00:00"))
      end
    end

    context "when LLM returns confidence below DATETIME_MIN_CONFIDENCE (0.75)" do
      before do
        stub_llm(content: {
          "service_index"     => nil,
          "starts_at"         => "2026-05-09T15:00:00",
          "address"           => nil,
          "confirmation"      => nil,
          "confidences"       => empty_confidences.merge("datetime" => 0.6),
          "service_alternates" => []
        })
      end

      it "returns nil for starts_at" do
        expect(call("el viernes").value![:slots][:starts_at]).to be_nil
      end
    end

    context "when LLM returns null starts_at (partial expression — day only)" do
      before do
        stub_llm(content: {
          "service_index"     => nil,
          "starts_at"         => nil,
          "address"           => nil,
          "confirmation"      => nil,
          "confidences"       => empty_confidences.merge("datetime" => 0.3),
          "service_alternates" => []
        })
      end

      it "returns nil for starts_at" do
        expect(call("el viernes").value![:slots][:starts_at]).to be_nil
      end
    end

    context "when LLM returns an ISO string with a timezone suffix despite instructions" do
      before do
        stub_llm(content: {
          "service_index"     => nil,
          "starts_at"         => "2026-05-08T10:00:00-06:00",
          "address"           => nil,
          "confirmation"      => nil,
          "confidences"       => empty_confidences.merge("datetime" => 0.9),
          "service_alternates" => []
        })
      end

      it "strips the offset and interprets the wall-clock time as Mexico_City local" do
        result = call("mañana a las 10")
        time   = result.value![:slots][:starts_at]
        expect(time.in_time_zone("America/Mexico_City").strftime("%Y-%m-%d %H:%M")).to eq("2026-05-08 10:00")
      end
    end
  end

  # ── Multi-slot: service + datetime in one message ────────────────────────────

  describe "multi-slot extraction" do
    context "when the message contains both a service and a datetime" do
      before do
        stub_llm(content: {
          "service_index"     => 1,
          "starts_at"         => "2026-05-09T15:00:00",
          "address"           => nil,
          "confirmation"      => nil,
          "confidences"       => empty_confidences.merge("service" => 0.9, "datetime" => 0.88),
          "service_alternates" => []
        })
      end

      it "returns both service and starts_at slots" do
        result = call("quiero un corte el viernes a las 3")
        slots  = result.value![:slots]
        expect(slots[:service]).to eq(corte)
        expect(slots[:starts_at]).to eq(Time.zone.parse("2026-05-09T15:00:00"))
      end
    end
  end

  # ── Address extraction ───────────────────────────────────────────────────────

  describe "address slot" do
    context "when LLM returns a high-confidence address" do
      before do
        stub_llm(content: {
          "service_index"     => nil,
          "starts_at"         => nil,
          "address"           => "Insurgentes 123",
          "confirmation"      => nil,
          "confidences"       => empty_confidences.merge("address" => 0.92),
          "service_alternates" => []
        })
      end

      it "returns the address string" do
        expect(call.value![:slots][:address]).to eq("Insurgentes 123")
      end
    end

    context "when address confidence is below ADDRESS_MIN_CONFIDENCE (0.7)" do
      before do
        stub_llm(content: {
          "service_index"     => nil,
          "starts_at"         => nil,
          "address"           => "algún lugar",
          "confirmation"      => nil,
          "confidences"       => empty_confidences.merge("address" => 0.5),
          "service_alternates" => []
        })
      end

      it "returns nil for address" do
        expect(call.value![:slots][:address]).to be_nil
      end
    end
  end

  # ── Confirmation extraction ──────────────────────────────────────────────────

  describe "confirmation slot" do
    context "when LLM returns high-confidence 'confirmed'" do
      before do
        stub_llm(content: {
          "service_index"     => nil,
          "starts_at"         => nil,
          "address"           => nil,
          "confirmation"      => "confirmed",
          "confidences"       => empty_confidences.merge("confirmation" => 0.93),
          "service_alternates" => []
        })
      end

      it "returns :confirmed" do
        expect(call("sí, está bien").value![:slots][:confirmation]).to eq(:confirmed)
      end
    end

    context "when LLM returns high-confidence 'cancelled'" do
      before do
        stub_llm(content: {
          "service_index"     => nil,
          "starts_at"         => nil,
          "address"           => nil,
          "confirmation"      => "cancelled",
          "confidences"       => empty_confidences.merge("confirmation" => 0.9),
          "service_alternates" => []
        })
      end

      it "returns :cancelled" do
        expect(call("mejor no gracias").value![:slots][:confirmation]).to eq(:cancelled)
      end
    end

    context "when confirmation confidence is below threshold" do
      before do
        stub_llm(content: {
          "service_index"     => nil,
          "starts_at"         => nil,
          "address"           => nil,
          "confirmation"      => "confirmed",
          "confidences"       => empty_confidences.merge("confirmation" => 0.6),
          "service_alternates" => []
        })
      end

      it "returns nil for confirmation" do
        expect(call("tal vez").value![:slots][:confirmation]).to be_nil
      end
    end
  end

  # ── top_candidates for Phase 4 disambiguation ───────────────────────────────

  describe "top_candidates" do
    context "when LLM returns alternates with confidence >= 0.5" do
      before do
        stub_llm(content: {
          "service_index"     => 1,
          "starts_at"         => nil,
          "address"           => nil,
          "confirmation"      => nil,
          "confidences"       => empty_confidences.merge("service" => 0.65),
          "service_alternates" => [
            { "index" => 3, "confidence" => 0.55 }
          ]
        })
      end

      it "returns the alternate Service objects" do
        # service_index=1 is below SERVICE_MIN_CONFIDENCE, so primary is nil;
        # alternate index 3 is above candidate threshold
        result = call
        expect(result.value![:top_candidates]).to include(manicure)
      end

      it "excludes the primary service_index from alternates" do
        result = call
        expect(result.value![:top_candidates]).not_to include(corte)
      end
    end

    context "when alternate confidence is below SERVICE_CANDIDATE_THRESHOLD (0.5)" do
      before do
        stub_llm(content: {
          "service_index"     => nil,
          "starts_at"         => nil,
          "address"           => nil,
          "confirmation"      => nil,
          "confidences"       => empty_confidences,
          "service_alternates" => [
            { "index" => 2, "confidence" => 0.3 }
          ]
        })
      end

      it "returns an empty array" do
        expect(call.value![:top_candidates]).to be_empty
      end
    end

    context "when LLM returns more than 2 alternates" do
      before do
        stub_llm(content: {
          "service_index"     => nil,
          "starts_at"         => nil,
          "address"           => nil,
          "confirmation"      => nil,
          "confidences"       => empty_confidences,
          "service_alternates" => [
            { "index" => 1, "confidence" => 0.7 },
            { "index" => 2, "confidence" => 0.65 },
            { "index" => 3, "confidence" => 0.6 }
          ]
        })
      end

      it "caps at 2 candidates" do
        expect(call.value![:top_candidates].length).to be <= 2
      end
    end
  end

  # ── Error handling ───────────────────────────────────────────────────────────

  describe "error handling" do
    context "when the LLM raises Llm::Port::Error" do
      before { allow(llm).to receive(:call).and_raise(Llm::Port::Error, "timeout") }

      it "returns Failure(:llm_error)" do
        result = call
        expect(result).to be_failure
        expect(result.failure).to eq(:llm_error)
      end
    end

    context "when the LLM response is malformed (missing confidences key)" do
      before do
        stub_llm(content: {
          "service_index"     => 1,
          "starts_at"         => "2026-05-09T15:00:00",
          "address"           => nil,
          "confirmation"      => nil,
          "service_alternates" => []
          # "confidences" is absent
        })
      end

      it "still returns Success (defaults to 0 confidences → nil slots)" do
        result = call
        expect(result).to be_success
        expect(result.value![:slots][:service]).to be_nil
        expect(result.value![:slots][:starts_at]).to be_nil
      end
    end
  end
end
