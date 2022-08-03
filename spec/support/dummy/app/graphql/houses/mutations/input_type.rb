Houses::Mutations::InputType = GraphQL::InputObjectType.define do
  name 'HouseInputType'
  description 'Properties for updating a House'

  argument :street, types.String
  argument :number, types.Int
  argument :price, types.Float
  argument :energy_grade, types.Int
  argument :principal, types.Boolean
  argument :user_id, types.String
  argument :city_id, types.String

end
