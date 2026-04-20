# frozen_string_literal: true

class Service < ApplicationRecord
  acts_as_tenant :account

  belongs_to :account
  has_many :bookings, dependent: :restrict_with_error

  monetize :price_cents, with_model_currency: :MXN
  monetize :deposit_amount_cents, with_model_currency: :MXN

  validates :name, presence: true
  validates :duration_minutes, numericality: { greater_than: 0 }
  validates :price_cents, numericality: { greater_than_or_equal_to: 0 }
  validates :deposit_amount_cents, numericality: { greater_than_or_equal_to: 0 }

  scope :active, -> { where(active: true) }

  def deposit_required?
    deposit_amount_cents > 0
  end

  def duration_label
    hours = duration_minutes / 60
    minutes = duration_minutes % 60
    parts = []
    parts << "#{hours}h" if hours > 0
    parts << "#{minutes}min" if minutes > 0
    parts.join(" ")
  end
end
