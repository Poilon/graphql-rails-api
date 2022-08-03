Cities::Mutations::Update = GraphQL::Field.define do
  description 'Updates a City'
  type Cities::Type

  argument :id, types.String
  argument :city, !Cities::Mutations::InputType

  resolve ApplicationService.call(:city, :update)
end
