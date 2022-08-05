class House < ApplicationRecord
  belongs_to :city
  belongs_to :user
  enum energy_grade: {
    a: 0,
    b: 1,
    c: 2,
    d: 3,
  }

end
