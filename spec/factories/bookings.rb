FactoryBot.define do
  factory :booking do
    association :account
    customer      { association :customer, account: account }
    service       { association :service,  account: account }
    user          { association :user,     account: account }
    starts_at     { 2.days.from_now }
    ends_at       { 2.days.from_now + 60.minutes }
    status        { "pending" }
    deposit_state { "not_required" }

    trait :confirmed do
      status       { "confirmed" }
      confirmed_at { Time.current }
    end

    trait :cancelled do
      status { "cancelled" }
    end
  end
end
