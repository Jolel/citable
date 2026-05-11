# frozen_string_literal: true

module TwilioWebhook
  # Builds a recent-conversation context array for injection into LLM prompts.
  # Each element is { role: "user"|"assistant"|"context", body: String }.
  #
  # - "user" entries: inbound WhatsApp logs (customer messages).
  # - "assistant" entries: outbound WhatsApp logs (bot replies).
  # - "context" entry (at most one, appended last): past completed bookings
  #   so the LLM can resolve "el mismo de siempre" or "como la vez pasada".
  #
  # Capped at TOTAL_CAP characters to limit prompt token spend.
  # Only looks back WINDOW (30 minutes) — matches WhatsappConversation::EXPIRATION_WINDOW
  # so the LLM sees the same horizon a customer would perceive as "the current chat".
  module TurnHistory
    BODY_TRUNCATION = 280
    TOTAL_CAP       = 800
    WINDOW          = 30.minutes

    # @param account      [Account]
    # @param customer     [Customer, nil]
    # @param conversation [WhatsappConversation, nil] — unused, kept for API symmetry
    # @param limit        [Integer] max recent log pairs to include (default 3)
    # @return [Array<Hash{role: String, body: String}>] oldest-first; empty when customer is nil
    def self.for(account:, customer:, conversation: nil, limit: 3)
      return [] unless customer

      logs = account.message_logs
                    .where(customer: customer, channel: "whatsapp")
                    .where(created_at: WINDOW.ago..)
                    .order(created_at: :desc)
                    .limit(limit * 2)
                    .to_a
                    .reverse

      turns = logs.filter_map do |log|
        role = log.direction == "inbound" ? "user" : "assistant"
        body = log.body.to_s.truncate(BODY_TRUNCATION)
        { role: role, body: body } if body.present?
      end

      ctx = past_booking_context(customer, account)
      turns << { role: "context", body: ctx } if ctx

      enforce_cap(turns)
    end

    # ── private helpers ───────────────────────────────────────────────────────

    def self.past_booking_context(customer, account)
      bookings = customer.bookings
                         .where(status: "completed", account: account)
                         .order(starts_at: :desc)
                         .limit(2)
      return nil if bookings.empty?

      parts = bookings.map do |b|
        date = b.starts_at.in_time_zone(account.timezone).strftime("%Y-%m-%d")
        svc  = b.service&.name
        svc ? "#{date} #{svc}" : date
      end
      "Citas previas del cliente: #{parts.join(", ")}"
    end
    private_class_method :past_booking_context

    def self.enforce_cap(turns)
      total = turns.sum { |t| t[:body].length }
      return turns if total <= TOTAL_CAP

      context = turns.last&.dig(:role) == "context" ? turns.pop : nil
      budget  = TOTAL_CAP - (context ? context[:body].length : 0)

      kept = []
      turns.reverse_each do |t|
        break if kept.sum { |k| k[:body].length } + t[:body].length > budget

        kept.unshift(t)
      end

      kept << context if context
      kept
    end
    private_class_method :enforce_cap
  end
end
