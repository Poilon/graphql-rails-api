Houses::Type = GraphQL::ObjectType.define do
  name 'House'
  field :id, !types.String
  field :created_at, types.String
  field :updated_at, types.String
  field :street, types.String
  field :number, types.Int
  field :price, types.Float
  field :energy_grade, types.Int
  field :principal, types.Boolean
  field :user_id, types.String
  field :user, Users::Type
  field :city_id, types.String
  field :city, Cities::Type
end
