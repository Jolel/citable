# frozen_string_literal: true

require "net/http"
require "json"

module Llm
  class Client
    Error = Class.new(StandardError)

    ENDPOINT = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent"
    MODEL    = "gemini-2.0-flash"
    TIMEOUT  = 4 # seconds

    def self.call(...) = new.call(...)

    # Returns { content: Hash, input_tokens: Integer, output_tokens: Integer, model: String }
    # Raises Llm::Client::Error on network failure, timeout, or bad response.
    def call(system:, user:, schema:)
      raw = post(system: system, user: user, schema: schema)
      parse(raw)
    end

    private

    def api_key
      @api_key ||= Rails.application.credentials.dig(:gemini, :api_key).presence ||
        raise(Error, "Gemini API key not configured (credentials.gemini.api_key)")
    end

    def post(system:, user:, schema:)
      uri  = URI("#{ENDPOINT}?key=#{api_key}")
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

      {
        content:       content,
        input_tokens:  usage["promptTokenCount"].to_i,
        output_tokens: usage["candidatesTokenCount"].to_i,
        model:         MODEL
      }
    rescue JSON::ParserError => e
      raise Error, "Gemini returned invalid JSON: #{e.message}"
    end
  end
end
