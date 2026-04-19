FactoryBot.define do
  factory :reminder_schedule do
    association :account
    association :booking
    kind          { "24h" }
    scheduled_for { 1.day.from_now }
    sent_at       { nil }

    trait :sent do
      sent_at { 1.hour.ago }
    end

    trait :for_2h do
      kind          { "2h" }
      scheduled_for { 2.hours.from_now }
    end
  end
end
