FactoryBot.define do
  factory :user do
    association :account
    sequence(:name)  { |n| "Usuario #{n}" }
    sequence(:email) { |n| "usuario#{n}@example.com" }
    password              { "password123" }
    password_confirmation { "password123" }
    role { "staff" }

    trait :owner do
      role { "owner" }
    end
  end
end
