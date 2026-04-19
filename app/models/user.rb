class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :trackable, :validatable,
         :omniauthable, omniauth_providers: [ :google_oauth2 ]

  belongs_to :account
  has_many :staff_availabilities, dependent: :destroy
  has_many :bookings, dependent: :restrict_with_error

  enum :role, { owner: "owner", staff: "staff" }, default: "staff"

  validates :name, presence: true
  validates :role, presence: true

  scope :owners, -> { where(role: "owner") }
  scope :staff_members, -> { where(role: "staff") }

  def google_connected?
    google_oauth_token.present?
  end

  def google_token_expired?
    google_token_expires_at.present? && google_token_expires_at <= Time.current
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
