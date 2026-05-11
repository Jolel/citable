# frozen_string_literal: true

require "dry/struct"

module Llm
  class Response < Dry::Struct
    attribute :content,       Citable::Types::Hash
    attribute :input_tokens,  Citable::Types::Integer
    attribute :output_tokens, Citable::Types::Integer
    attribute :model,         Citable::Types::String
    attribute? :latency_ms,   Citable::Types::Integer.default(0)
  end
end
