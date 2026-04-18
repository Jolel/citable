class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :trackable, :validatable

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

  def display_name
    name.presence || email
  end
end
