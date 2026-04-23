# frozen_string_literal: true

require "dry/monads"
require_relative "../../citable/import"
require_relative "../errors"

module Core
  module UseCases
    class SendWhatsappMessage
      include Dry::Monads[:result]
      include Citable::Import["infrastructure.adapters.twilio_adapter"]

      # @param to   [String] E.164 destination phone number
      # @param from [String] E.164 sender number (the Twilio WhatsApp number)
      # @param body [String] message text
      # @return [Dry::Monads::Result<SentMessage, Core::Errors::ExternalServiceError>]
      def call(to:, from:, body:)
        sent = twilio_adapter.send_message(to: to, from: from, body: body)
        Success(sent)
      rescue Core::Errors::ExternalServiceError => e
        Failure(e)
      end
    end
  end
end
