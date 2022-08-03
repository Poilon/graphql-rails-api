Houses::Mutations::Create = GraphQL::Field.define do
  description 'Creates a House'
  type Houses::Type

  argument :house, !Houses::Mutations::InputType

  resolve ApplicationService.call(:house, :create)
end
