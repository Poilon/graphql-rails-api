Accounts::Mutations::Update = GraphQL::Field.define do
  description 'Updates a Account'
  type Accounts::Type

  argument :id, types.String
  argument :account, !Accounts::Mutations::InputType

  resolve ApplicationService.call(:account, :update)
end
