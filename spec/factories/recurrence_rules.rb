FactoryBot.define do
  factory :recurrence_rule do
    association :account
    frequency { "weekly" }
    interval { 1 }
    ends_on { nil }

    trait :biweekly do
      frequency { "biweekly" }
    end

    trait :monthly do
      frequency { "monthly" }
    end

    trait :with_end_date do
      ends_on { 3.months.from_now.to_date }
    end
  end
end
