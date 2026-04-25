FactoryBot.define do
  factory :account do
    sequence(:name) { |n| "Business #{n}" }
    timezone { "America/Mexico_City" }
    locale { "es-MX" }
    plan { "free" }
    sequence(:whatsapp_number) { |n| "1555000#{n.to_s.rjust(4, '0')}" }
    whatsapp_quota_used { 0 }

    trait :pro do
      plan { "pro" }
    end

    trait :quota_exceeded do
      whatsapp_quota_used { 100 }
    end

    trait :pro_quota_exceeded do
      plan { "pro" }
      whatsapp_quota_used { 1000 }
    end
  end
end
