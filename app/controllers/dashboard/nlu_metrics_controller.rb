# frozen_string_literal: true

class Dashboard::NluMetricsController < Dashboard::BaseController
  WINDOW_DAYS = 30
  LOW_CONFIDENCE_THRESHOLD = 0.65

  def index
    base = current_account.message_logs
                          .inbound
                          .where.not(ai_model: nil)
                          .where(created_at: WINDOW_DAYS.days.ago..)

    @logs = base.order(created_at: :desc)

    @total_calls    = base.count
    @intent_counts  = base.where.not(ai_intent: nil).group(:ai_intent).count.sort_by { |_, v| -v }
    @low_conf_count = base.where("ai_confidence < ?", LOW_CONFIDENCE_THRESHOLD)
                          .where.not(ai_confidence: nil).count
    @low_conf_rate  = @total_calls > 0 ? (@low_conf_count.to_f / @total_calls * 100).round(1) : 0

    latency_values = base.where.not(ai_latency_ms: nil).pluck(:ai_latency_ms).sort
    @p50_latency   = percentile(latency_values, 50)
    @p95_latency   = percentile(latency_values, 95)

    @total_input_tokens  = base.sum(:ai_input_tokens)
    @total_output_tokens = base.sum(:ai_output_tokens)

    @prompt_versions = base.where.not(ai_prompt_version: nil).group(:ai_prompt_version).count
  end

  private

  def percentile(sorted_values, pct)
    return nil if sorted_values.empty?
    idx = ((sorted_values.length - 1) * pct / 100.0).round
    sorted_values[idx]
  end
end
