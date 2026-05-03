# frozen_string_literal: true

require "net/http"
require "json"

module Llm
  # Gemini implementation of the Llm::Port contract.
  # Override the model at runtime via credentials (gemini.model).
  # Verify the current model ID at https://ai.google.dev/gemini-api/docs/models
  class GeminiAdapter < Port
    DEFAULT_MODEL = "gemini-2.5-pro"
    TIMEOUT       = 4 # seconds

    def initialize(api_key: nil, model: nil)
      @api_key_override = api_key
      @model_override   = model
    end

    def call(system:, user:, schema:)
      raw = post(system: system, user: user, schema: schema)
      parse(raw)
    end

    private

    def model
      @model_override.presence ||
        Rails.application.credentials.dig(:gemini, :model).presence ||
        DEFAULT_MODEL
    end

    def endpoint
      "https://generativelanguage.googleapis.com/v1beta/models/#{model}:generateContent"
    end

    def api_key
      @api_key ||= @api_key_override.presence ||
        Rails.application.credentials.dig(:gemini, :api_key).presence ||
        raise(Error, "Gemini API key not configured (credentials.gemini.api_key)")
    end

    def post(system:, user:, schema:)
      uri  = URI("#{endpoint}?key=#{api_key}")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl      = true
      http.open_timeout = TIMEOUT
      http.read_timeout = TIMEOUT

      req = Net::HTTP::Post.new(uri.request_uri, "Content-Type" => "application/json")
      req.body = build_body(system: system, user: user, schema: schema).to_json

      response = http.request(req)
      raise Error, "Gemini API returned #{response.code}: #{response.body.truncate(200)}" unless response.is_a?(Net::HTTPSuccess)

      response.body
    rescue Net::OpenTimeout, Net::ReadTimeout => e
      raise Error, "Gemini API timeout: #{e.message}"
    rescue Error
      raise
    rescue => e
      raise Error, "Gemini API error: #{e.message}"
    end

    def build_body(system:, user:, schema:)
      {
        system_instruction: { parts: [ { text: system } ] },
        contents: [ { role: "user", parts: [ { text: user } ] } ],
        generationConfig: {
          responseMimeType: "application/json",
          responseSchema: schema
        }
      }
    end

    def parse(body)
      data = JSON.parse(body)
      text = data.dig("candidates", 0, "content", "parts", 0, "text")
      raise Error, "Empty response from Gemini" if text.blank?

      content = JSON.parse(text)
      usage   = data["usageMetadata"] || {}

      Llm::Response.new(
        content:       content,
        input_tokens:  usage["promptTokenCount"].to_i,
        output_tokens: usage["candidatesTokenCount"].to_i,
        model:         model
      )
    rescue JSON::ParserError => e
      raise Error, "Gemini returned invalid JSON: #{e.message}"
    end
  end
end
