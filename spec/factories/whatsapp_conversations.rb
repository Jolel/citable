FactoryBot.define do
  factory :whatsapp_conversation do
    association :account
    from_phone { "5215512345678" }
    step { "awaiting_name" }
    metadata { {} }
  end
end
