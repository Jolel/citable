# frozen_string_literal: true

require "dry/struct"
require_relative "../../core/errors"
require_relative "../../citable/import"

module Infrastructure
  module Adapters
    class TwilioAdapter
      module Types
        include Dry.Types()
      end

      # Typed input — validates at the boundary; no SDK types enter the domain
      class OutboundMessage < Dry::Struct
        attribute :to,   Types::Strict::String
        attribute :from, Types::Strict::String
        attribute :body, Types::Strict::String
      end

      # Typed output — the Twilio::REST::Message object never leaks past this adapter
      class SentMessage < Dry::Struct
        attribute :sid,    Types::Strict::String
        attribute :status, Types::Strict::String
      end

      include Citable::Import["twilio.client"]

      # @param to   [String] E.164 phone (no whatsapp: prefix)
      # @param from [String] E.164 sender (no whatsapp: prefix)
      # @param body [String] message text
      # @return [SentMessage]
      # @raise [Core::Errors::ExternalServiceError]
      def send_message(to:, from:, body:)
        msg = OutboundMessage.new(to: to, from: from, body: body)

        raw = twilio_client.messages.create(
          from: "whatsapp:#{msg.from}",
          to:   "whatsapp:#{msg.to}",
          body: msg.body
        )

        SentMessage.new(sid: raw.sid, status: raw.status)
      rescue Twilio::REST::TwilioError => e
        raise Core::Errors::ExternalServiceError.new(e.message, original: e)
      end
    end
  end
end
