Cities::Mutations::Create = GraphQL::Field.define do
  description 'Creates a City'
  type Cities::Type

  argument :city, !Cities::Mutations::InputType

  resolve ApplicationService.call(:city, :create)
end
