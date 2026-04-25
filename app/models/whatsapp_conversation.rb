# frozen_string_literal: true

class WhatsappConversation < ApplicationRecord
  EXPIRATION_WINDOW = 30.minutes
  STEPS = %w[
    awaiting_name
    awaiting_service
    awaiting_datetime
    awaiting_address
    confirming_booking
    completed
    cancelled
  ].freeze

  belongs_to :account
  belongs_to :customer, optional: true
  belongs_to :service, optional: true
  belongs_to :booking, optional: true

  before_validation :normalize_from_phone

  validates :from_phone, presence: true
  validates :step, presence: true
  validates :step, inclusion: { in: STEPS }

  scope :active, -> { where(updated_at: EXPIRATION_WINDOW.ago..) }
  scope :open, -> { where.not(step: %w[completed cancelled]) }

  def complete!
    update!(step: "completed")
  end

  private

  def normalize_from_phone
    self.from_phone = Account.normalize_whatsapp_number(from_phone)
  end
end
