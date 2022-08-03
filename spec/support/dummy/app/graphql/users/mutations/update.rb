Users::Mutations::Update = GraphQL::Field.define do
  description 'Updates a User'
  type Users::Type

  argument :id, types.String
  argument :user, !Users::Mutations::InputType

  resolve ApplicationService.call(:user, :update)
end
