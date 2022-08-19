class User < ApplicationRecord
  has_many :houses
  has_one :account

end
