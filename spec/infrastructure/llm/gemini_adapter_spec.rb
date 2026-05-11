# frozen_string_literal: true

require "rails_helper"
require_relative "port_contract_spec"

RSpec.describe Llm::GeminiAdapter do
  let(:api_key)  { "test-gemini-key" }
  let(:endpoint) do
    "https://generativelanguage.googleapis.com/v1beta/models/#{Llm::GeminiAdapter::DEFAULT_MODEL}:generateContent?key=#{api_key}"
  end

  before do
    allow(Rails.application.credentials).to receive(:dig).and_call_original
    allow(Rails.application.credentials).to receive(:dig).with(:gemini, :api_key).and_return(api_key)
    allow(Rails.application.credentials).to receive(:dig).with(:gemini, :model).and_return(nil)
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

  it_behaves_like "an LLM port" do
    let(:adapter)      { described_class.new }
    let(:stub_success) { -> { stub_gemini(body: { candidates: [ { content: { parts: [ { text: { foo: "bar" }.to_json } ] } } ], usageMetadata: { promptTokenCount: 1, candidatesTokenCount: 1 } }.to_json) } }
    let(:stub_failure) { -> { stub_request(:post, endpoint).to_timeout } }
  end

  describe "#call" do
    let(:schema) { { type: "object", properties: { starts_at: { type: "string" }, confidence: { type: "number" } } } }

    context "when the API returns a valid response" do
      before { stub_gemini }

      it "returns an Llm::Response with content, token counts and model name" do
        result = described_class.new.call(system: "sys", user: "user", schema: schema)

        expect(result).to be_a(Llm::Response)
        expect(result.content).to eq("starts_at" => "2026-05-02T15:00:00", "confidence" => 0.95)
        expect(result.input_tokens).to eq(120)
        expect(result.output_tokens).to eq(30)
        expect(result.model).to eq(Llm::GeminiAdapter::DEFAULT_MODEL)
      end
    end

    context "when the API returns a non-2xx status" do
      before { stub_gemini(status: 503, body: "Service Unavailable") }

      it "raises Llm::Port::Error" do
        expect { described_class.new.call(system: "sys", user: "user", schema: schema) }
          .to raise_error(Llm::Port::Error, /503/)
      end
    end

    context "when the response JSON is malformed" do
      before { stub_gemini(body: "not-json") }

      it "raises Llm::Port::Error" do
        expect { described_class.new.call(system: "sys", user: "user", schema: schema) }
          .to raise_error(Llm::Port::Error, /invalid JSON/i)
      end
    end

    context "when the response contains no text" do
      before do
        stub_gemini(body: { candidates: [ { content: { parts: [ { text: "" } ] } } ],
                            usageMetadata: {} }.to_json)
      end

      it "raises Llm::Port::Error" do
        expect { described_class.new.call(system: "sys", user: "user", schema: schema) }
          .to raise_error(Llm::Port::Error, /empty response/i)
      end
    end

    context "when the request times out" do
      before { stub_request(:post, endpoint).to_timeout }

      it "raises Llm::Port::Error" do
        expect { described_class.new.call(system: "sys", user: "user", schema: schema) }
          .to raise_error(Llm::Port::Error, /timeout/i)
      end
    end

    context "when the API key is not configured" do
      before do
        allow(Rails.application.credentials).to receive(:dig).with(:gemini, :api_key).and_return(nil)
      end

      it "raises Llm::Port::Error" do
        expect { described_class.new.call(system: "sys", user: "user", schema: schema) }
          .to raise_error(Llm::Port::Error, /not configured/i)
      end
    end

    context "with a custom model override" do
      let(:custom_model) { "gemini-1.5-pro" }
      let(:custom_endpoint) do
        "https://generativelanguage.googleapis.com/v1beta/models/#{custom_model}:generateContent?key=#{api_key}"
      end

      before do
        stub_request(:post, custom_endpoint)
          .to_return(status: 200, body: gemini_response, headers: { "Content-Type" => "application/json" })
      end

      it "uses the overridden model in the endpoint and the response" do
        result = described_class.new(model: custom_model).call(system: "s", user: "u", schema: schema)

        expect(result.model).to eq(custom_model)
        expect(WebMock).to have_requested(:post, custom_endpoint)
      end
    end
  end
end
