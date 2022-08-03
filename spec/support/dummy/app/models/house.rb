class House < ApplicationRecord
  belongs_to :city
  belongs_to :user
  enum energy_grade: {
    bad: 0,
    average: 1,
    good: 2,
  }

end
