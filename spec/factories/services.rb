FactoryBot.define do
  factory :service do
    association :account
    sequence(:name) { |n| "Service #{n}" }
    duration_minutes { 60 }
    price_cents { 50000 }
    deposit_amount_cents { 0 }
    active { true }
    requires_address { false }

    trait :with_deposit do
      deposit_amount_cents { 10000 }
    end

    trait :requires_address do
      requires_address { true }
    end

    trait :inactive do
      active { false }
    end
  end
end
