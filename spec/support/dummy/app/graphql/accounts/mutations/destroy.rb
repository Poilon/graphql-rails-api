Accounts::Mutations::Destroy = GraphQL::Field.define do
  description 'Destroys a Account'
  type Accounts::Type

  argument :id, !types.String

  resolve ApplicationService.call(:account, :destroy)
end
