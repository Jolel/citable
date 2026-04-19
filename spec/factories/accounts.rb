FactoryBot.define do
  factory :account do
    sequence(:name)     { |n| "Negocio #{n}" }
    sequence(:subdomain) { |n| "negocio-#{n}" }
    timezone            { "America/Mexico_City" }
    locale              { "es-MX" }
    plan                { "free" }
    whatsapp_quota_used { 0 }
  end
end
