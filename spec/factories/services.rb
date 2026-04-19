FactoryBot.define do
  factory :service do
    association :account
    sequence(:name)      { |n| "Servicio #{n}" }
    duration_minutes     { 60 }
    price_cents          { 50000 }
    deposit_amount_cents { 0 }
    active               { true }
    requires_address     { false }
  end
end
