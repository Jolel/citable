FactoryBot.define do
  factory :customer do
    association :account
    sequence(:name)  { |n| "Cliente #{n}" }
    sequence(:phone) { |n| "+5255500#{n.to_s.rjust(5, '0')}" }
  end
end
