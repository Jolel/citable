# frozen_string_literal: true

class MessageLog < ApplicationRecord
  acts_as_tenant :account

  CHANNELS = %w[whatsapp email].freeze
  DIRECTIONS = %w[outbound inbound].freeze
  STATUSES = %w[pending sent delivered failed].freeze

  belongs_to :account
  belongs_to :booking, optional: true
  belongs_to :customer, optional: true

  validates :channel, inclusion: { in: CHANNELS }
  validates :direction, inclusion: { in: DIRECTIONS }
  validates :body, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :outbound, -> { where(direction: "outbound") }
  scope :inbound, -> { where(direction: "inbound") }
  scope :whatsapp, -> { where(channel: "whatsapp") }
  scope :email, -> { where(channel: "email") }
  scope :recent, -> { order(created_at: :desc) }
end
