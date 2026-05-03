# frozen_string_literal: true

module Llm
  # Outbound port — the contract every LLM adapter (Gemini, future Anthropic,
  # fakes for tests) must satisfy. Application services depend on this, never
  # on a concrete adapter.
  class Port
    Error = Class.new(StandardError)

    # @param system [String] System instructions for the model.
    # @param user   [String] User message.
    # @param schema [Hash]   JSON Schema for structured output.
    # @return [Llm::Response]
    # @raise  [Llm::Port::Error] on timeout, transport, or parse failure.
    def call(system:, user:, schema:)
      raise NotImplementedError, "#{self.class} must implement #call"
    end
  end
end
