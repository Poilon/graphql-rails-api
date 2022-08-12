require 'factory_bot'
require 'faker'

FactoryBot.define do
  factory :user do
    first_name { Faker::Name.first_name }
    last_name  { Faker::Name.last_name }
    email      { Faker::Internet.email }
    account
  end

  factory :account do
  end

  factory :city do
    name { Faker::Address.city }
  end

  factory :house do
    street { Faker::Address.street_name }
    number { Faker::Number.number(digits: 2) }
    price { Faker::Number.number(digits: 2) }
    energy_grade { House.energy_grades.keys.sample }
    principal { Faker::Boolean.boolean }
    build_at { Faker::Date.backward(days: 365) }
    user
    city
  end
end