class Booking < ApplicationRecord
  acts_as_tenant :account

  belongs_to :account
  belongs_to :customer
  belongs_to :service
  belongs_to :user
  belongs_to :recurrence_rule, optional: true
  has_many :message_logs, dependent: :destroy
  has_many :reminder_schedules, dependent: :destroy

  attr_accessor :skip_google_sync

  enum :status, {
    pending: "pending",
    confirmed: "confirmed",
    cancelled: "cancelled",
    no_show: "no_show",
    completed: "completed"
  }, default: "pending"

  enum :deposit_state, {
    not_required: "not_required",
    deposit_pending: "pending",
    deposit_paid: "paid",
    deposit_refunded: "refunded"
  }, default: "not_required"

  validates :starts_at, presence: true
  validates :ends_at, presence: true
  validates :status, presence: true
  validates :deposit_state, presence: true
  validate :ends_at_after_starts_at
  validate :address_required_for_service

  scope :upcoming, -> { where("starts_at > ?", Time.current).order(:starts_at) }
  scope :past, -> { where("starts_at <= ?", Time.current).order(starts_at: :desc) }
  scope :today, -> { where(starts_at: Time.current.beginning_of_day..Time.current.end_of_day) }
  scope :active, -> { where(status: %w[pending confirmed]) }

  before_validation :set_ends_at

  after_create_commit  :enqueue_google_calendar_create
  after_update_commit  :enqueue_google_calendar_update

  def confirm!
    update!(status: :confirmed, confirmed_at: Time.current)
  end

  def cancel!
    self.skip_google_sync = true
    update!(status: :cancelled)
    GoogleCalendarSyncJob.perform_later(id, "cancel")
  end

  def recurring?
    recurrence_rule_id.present?
  end

  def deposit_required?
    service&.deposit_required?
  end

  private

  def set_ends_at
    return if ends_at.present? || starts_at.blank? || service.blank?
    self.ends_at = starts_at + service.duration_minutes.minutes
  end

  def enqueue_google_calendar_create
    GoogleCalendarSyncJob.perform_later(id, "create")
  end

  def enqueue_google_calendar_update
    return if skip_google_sync
    return unless saved_change_to_starts_at? || saved_change_to_ends_at? || saved_change_to_status?

    GoogleCalendarSyncJob.perform_later(id, "update")
  end

  def ends_at_after_starts_at
    return unless starts_at && ends_at
    errors.add(:ends_at, "debe ser posterior a la hora de inicio") if ends_at <= starts_at
  end

  def address_required_for_service
    return unless service&.requires_address?
    errors.add(:address, "es requerida para este servicio") if address.blank?
  end
end
