# frozen_string_literal: true

class Customer < ApplicationRecord
  acts_as_tenant :account

  belongs_to :account
  has_many :bookings, dependent: :destroy
  has_many :message_logs, dependent: :destroy

  validates :name, presence: true
  validates :phone, presence: true,
                    format: { with: /\A\+?[\d\s\-().]+\z/, message: "formato inválido" }

  scope :with_tag, ->(tag) { where("? = ANY(tags)", tag) }
  scope :by_name, -> { order(:name) }

  def upcoming_bookings
    bookings.where("starts_at > ?", Time.current).order(:starts_at)
  end

  def past_bookings
    bookings.where("starts_at <= ?", Time.current).order(starts_at: :desc)
  end

  def normalized_phone
    phone.gsub(/\D/, "")
  end
end
