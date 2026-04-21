FactoryBot.define do
  factory :message_log do
    association :account
    association :booking
    association :customer
    channel { "whatsapp" }
    direction { "outbound" }
    body { "Test message body" }
    status { "sent" }

    trait :inbound do
      direction { "inbound" }
      status { "delivered" }
    end

    trait :failed do
      status { "failed" }
    end

    trait :email do
      channel { "email" }
    end
  end
end
