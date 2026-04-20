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

  validates :name, presence: true
  validates :subdomain, presence: true, uniqueness: { case_sensitive: false },
                        format: { with: /\A[a-z0-9\-]+\z/, message: "solo letras minúsculas, números y guiones" }
  validates :timezone, presence: true
  validates :locale, presence: true
  validates :plan, inclusion: { in: PLANS }
  validates :whatsapp_quota_used, numericality: { greater_than_or_equal_to: 0 }

  before_validation :downcase_subdomain

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

  private

  def downcase_subdomain
    self.subdomain = subdomain&.downcase&.strip
  end
end
