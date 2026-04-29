# frozen_string_literal: true

require "rails_helper"

RSpec.describe Llm::Client do
  let(:api_key)  { "test-gemini-key" }
  let(:endpoint) do
    "https://generativelanguage.googleapis.com/v1beta/models/#{Llm::Client::DEFAULT_MODEL}:generateContent?key=#{api_key}"
  end

  before do
    allow(Rails.application.credentials).to receive(:dig).and_call_original
    allow(Rails.application.credentials).to receive(:dig).with(:gemini, :api_key).and_return(api_key)
  end

  def gemini_response(starts_at: "2026-05-02T15:00:00", confidence: 0.95)
    {
      candidates: [
        { content: { parts: [ { text: { starts_at: starts_at, confidence: confidence }.to_json } ] } }
      ],
      usageMetadata: { promptTokenCount: 120, candidatesTokenCount: 30 }
    }.to_json
  end

  def stub_gemini(body: gemini_response, status: 200)
    stub_request(:post, endpoint)
      .to_return(status: status, body: body, headers: { "Content-Type" => "application/json" })
  end

  describe ".call" do
    let(:schema) { { type: "object", properties: { starts_at: { type: "string" }, confidence: { type: "number" } } } }

    context "when the API returns a valid response" do
      before { stub_gemini }

      it "returns content, token counts and model name" do
        result = described_class.call(system: "sys", user: "user", schema: schema)

        expect(result[:content]).to eq("starts_at" => "2026-05-02T15:00:00", "confidence" => 0.95)
        expect(result[:input_tokens]).to eq(120)
        expect(result[:output_tokens]).to eq(30)
        expect(result[:model]).to eq(Llm::Client::DEFAULT_MODEL)
      end
    end

    context "when the API returns a non-2xx status" do
      before { stub_gemini(status: 503, body: "Service Unavailable") }

      it "raises Llm::Client::Error" do
        expect { described_class.call(system: "sys", user: "user", schema: schema) }
          .to raise_error(Llm::Client::Error, /503/)
      end
    end

    context "when the response JSON is malformed" do
      before { stub_gemini(body: "not-json") }

      it "raises Llm::Client::Error" do
        expect { described_class.call(system: "sys", user: "user", schema: schema) }
          .to raise_error(Llm::Client::Error, /invalid JSON/i)
      end
    end

    context "when the response contains no text" do
      before do
        stub_gemini(body: { candidates: [ { content: { parts: [ { text: "" } ] } } ],
                            usageMetadata: {} }.to_json)
      end

      it "raises Llm::Client::Error" do
        expect { described_class.call(system: "sys", user: "user", schema: schema) }
          .to raise_error(Llm::Client::Error, /empty response/i)
      end
    end

    context "when the request times out" do
      before { stub_request(:post, endpoint).to_timeout }

      it "raises Llm::Client::Error" do
        expect { described_class.call(system: "sys", user: "user", schema: schema) }
          .to raise_error(Llm::Client::Error, /timeout/i)
      end
    end

    context "when the API key is not configured" do
      before do
        allow(Rails.application.credentials).to receive(:dig).with(:gemini, :api_key).and_return(nil)
      end

      it "raises Llm::Client::Error" do
        expect { described_class.call(system: "sys", user: "user", schema: schema) }
          .to raise_error(Llm::Client::Error, /not configured/i)
      end
    end
  end
end
