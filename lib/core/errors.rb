# frozen_string_literal: true

module Core
  module Errors
    class Error < StandardError; end

    class ExternalServiceError < Error
      attr_reader :original

      def initialize(message, original: nil)
        super(message)
        @original = original
      end
    end
  end
end
