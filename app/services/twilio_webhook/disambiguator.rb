# frozen_string_literal: true

module TwilioWebhook
  # Builds a targeted clarification question when slot extraction returned
  # medium-confidence candidates instead of a single confident match.
  #
  # Returns { message: String, metadata: Hash } — caller updates the
  # conversation step and merges metadata["disambiguation"] into the record.
  module Disambiguator
    def self.call(slot:, candidates:, conversation:)
      case slot.to_sym
      when :service then service_disambiguation(candidates)
      end
    end

    def self.service_disambiguation(candidates)
      numbered = candidates.each_with_index
                           .map { |svc, i| "#{i + 1}. *#{svc.name}*" }
                           .join(" o ")
      message  = "¿Te refieres a #{numbered}? Escribe el número o el nombre del servicio."
      metadata = { "slot" => "service", "candidates" => candidates.map(&:id) }
      { message:, metadata: }
    end
    private_class_method :service_disambiguation
  end
end
