# frozen_string_literal: true

class Account < ApplicationRecord
  PLANS = %w[free pro].freeze

  has_many :users, dependent: :destroy
  has_many :services, dependent: :destroy
  has_many :customers, dependent: :destroy
  has_many :bookings, dependent: :destroy
  has_many :recurrence_rules, dependent: :destroy
  has_many :message_logs, dependent: :destroy
  has_many :reminder_schedules, dependent: :destroy
  has_many :whatsapp_conversations, dependent: :destroy

  before_validation :normalize_whatsapp_number

  validates :name, presence: true
  validates :timezone, presence: true
  validates :locale, presence: true
  validates :plan, inclusion: { in: PLANS }
  validates :whatsapp_number, uniqueness: true, allow_blank: true
  validates :whatsapp_quota_used, numericality: { greater_than_or_equal_to: 0 }

  WHATSAPP_QUOTA = { "free" => 100, "pro" => 1000 }.freeze

  def whatsapp_quota_limit
    WHATSAPP_QUOTA.fetch(plan, 100)
  end

  def whatsapp_quota_exceeded?
    whatsapp_quota_used >= whatsapp_quota_limit
  end

  def free?
    plan == "free"
  end

  def pro?
    plan == "pro"
  end

  def self.normalize_whatsapp_number(value)
    value.to_s.gsub(/\D/, "").presence
  end

  private

  def normalize_whatsapp_number
    self.whatsapp_number = self.class.normalize_whatsapp_number(whatsapp_number)
  end
end
