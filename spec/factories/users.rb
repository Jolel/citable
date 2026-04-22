FactoryBot.define do
  factory :user do
    association :account
    sequence(:name) { |n| "User #{n}" }
    sequence(:email) { |n| "user#{n}@example.com" }
    password { "password123" }
    password_confirmation { "password123" }
    role { "staff" }

    trait :owner do
      role { "owner" }
    end

    trait :google_connected do
      google_oauth_token { "ya29.test_token" }
      google_refresh_token { "1//test_refresh" }
      google_token_expires_at { 1.hour.from_now }
      google_calendar_id { "primary" }
    end
  end
end
