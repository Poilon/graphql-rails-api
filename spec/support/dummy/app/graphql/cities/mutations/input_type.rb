Cities::Mutations::InputType = GraphQL::InputObjectType.define do
  name 'CityInputType'
  description 'Properties for updating a City'
  argument :house_ids, types[types.String]

  argument :name, types.String

end
