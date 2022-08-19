Users::Mutations::Create = GraphQL::Field.define do
  description 'Creates a User'
  type Users::Type

  argument :user, !Users::Mutations::InputType

  resolve ApplicationService.call(:user, :create)
end
