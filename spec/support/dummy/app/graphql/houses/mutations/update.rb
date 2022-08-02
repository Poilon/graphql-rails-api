Houses::Mutations::Update = GraphQL::Field.define do
  description 'Updates a House'
  type Houses::Type

  argument :id, types.String
  argument :house, !Houses::Mutations::InputType

  resolve ApplicationService.call(:house, :update)
end
