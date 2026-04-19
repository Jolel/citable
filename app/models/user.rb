class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :trackable, :validatable

  belongs_to :account
  has_many :staff_availabilities, dependent: :destroy
  has_many :bookings, dependent: :restrict_with_error

  enum :role, { owner: "owner", staff: "staff" }, default: "staff"

  encrypts :google_oauth_token
  encrypts :google_refresh_token
  encrypts :google_sync_token

  validates :name, presence: true
  validates :role, presence: true

  scope :owners, -> { where(role: "owner") }
  scope :staff_members, -> { where(role: "staff") }
  scope :google_connected, -> { where.not(google_oauth_token: nil) }

  def google_connected?
    google_oauth_token.present?
  end

  def google_token_expired?
    google_token_expires_at.present? && google_token_expires_at <= 5.minutes.from_now
  end

  def google_watch_expiring?
    google_channel_expires_at.present? && google_channel_expires_at <= 1.day.from_now
  end

  def disconnect_google!
    update!(
      google_oauth_token:      nil,
      google_refresh_token:    nil,
      google_token_expires_at: nil,
      google_calendar_id:      nil
    )
  end

  def display_name
    name.presence || email
  end
end
