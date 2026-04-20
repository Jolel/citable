# frozen_string_literal: true

class ReminderSchedule < ApplicationRecord
  KINDS = %w[24h 2h].freeze

  belongs_to :account
  belongs_to :booking

  validates :kind, inclusion: { in: KINDS }
  validates :scheduled_for, presence: true

  scope :pending, -> { where(sent_at: nil) }
  scope :sent, -> { where.not(sent_at: nil) }
  scope :due, -> { pending.where("scheduled_for <= ?", Time.current) }

  def sent?
    sent_at.present?
  end

  def mark_sent!
    update!(sent_at: Time.current)
  end
end
