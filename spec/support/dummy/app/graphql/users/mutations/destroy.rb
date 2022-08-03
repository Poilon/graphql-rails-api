Users::Mutations::Destroy = GraphQL::Field.define do
  description 'Destroys a User'
  type Users::Type

  argument :id, !types.String

  resolve ApplicationService.call(:user, :destroy)
end
