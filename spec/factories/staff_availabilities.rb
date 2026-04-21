FactoryBot.define do
  factory :staff_availability do
    association :account
    association :user
    day_of_week { 1 } # Monday
    start_time { "09:00" }
    end_time { "18:00" }
    active { true }

    trait :inactive do
      active { false }
    end
  end
end
