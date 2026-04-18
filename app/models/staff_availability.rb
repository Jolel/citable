class StaffAvailability < ApplicationRecord
  acts_as_tenant :account

  DAYS = %w[sunday monday tuesday wednesday thursday friday saturday].freeze

  belongs_to :account
  belongs_to :user

  validates :day_of_week, inclusion: { in: 0..6 }
  validates :start_time, presence: true
  validates :end_time, presence: true
  validate :end_time_after_start_time

  scope :active, -> { where(active: true) }
  scope :for_day, ->(day) { where(day_of_week: day) }

  def day_name
    DAYS[day_of_week]
  end

  private

  def end_time_after_start_time
    return unless start_time && end_time
    errors.add(:end_time, "debe ser posterior a la hora de inicio") if end_time <= start_time
  end
end
