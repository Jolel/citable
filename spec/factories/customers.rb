FactoryBot.define do
  factory :customer do
    association :account
    sequence(:name) { |n| "Customer #{n}" }
    sequence(:phone) { |n| "+521234#{n.to_s.rjust(6, '0')}" }
    tags { [] }
    custom_fields { {} }
  end
end
