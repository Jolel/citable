# frozen_string_literal: true

class RecurrenceRule < ApplicationRecord
  acts_as_tenant :account

  FREQUENCIES = %w[weekly biweekly monthly].freeze

  belongs_to :account
  has_many :bookings, dependent: :nullify

  validates :frequency, inclusion: { in: FREQUENCIES }
  validates :interval, numericality: { greater_than: 0 }

  def label
    case frequency
    when "weekly"    then "Semanal"
    when "biweekly"  then "Quincenal"
    when "monthly"   then "Mensual"
    end
  end

  def next_occurrence_after(date)
    case frequency
    when "weekly"   then date + interval.weeks
    when "biweekly" then date + (interval * 2).weeks
    when "monthly"  then date + interval.months
    end
  end

  def active_on?(date)
    return true if ends_on.nil?
    date.to_date <= ends_on
  end
end
