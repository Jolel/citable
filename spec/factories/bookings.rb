FactoryBot.define do
  factory :booking do
    association :account
    customer { association :customer, account: account }
    service  { association :service,  account: account }
    user     { association :user,     account: account }

    starts_at { 1.day.from_now.change(hour: 10, min: 0) }
    ends_at { nil } # set_ends_at callback will populate this
    status { "pending" }
    deposit_state { "not_required" }

    # Suppress callbacks that enqueue jobs so factory creation stays fast
    # and test isolation is easier.
    after(:build) do |booking|
      booking.skip_google_sync = true
    end

    trait :confirmed do
      status { "confirmed" }
      confirmed_at { 1.hour.ago }
    end

    trait :cancelled do
      status { "cancelled" }
    end

    trait :past do
      starts_at { 2.days.ago.change(hour: 10, min: 0) }
      ends_at { 2.days.ago.change(hour: 11, min: 0) }
      # The starts_at_in_future validation runs only on :create, so persist
      # past-dated fixtures by skipping validation rather than disabling the model rule.
      to_create { |instance| instance.save(validate: false) }
    end

    trait :with_deposit do
      deposit_state { "deposit_pending" }
    end
  end
end
