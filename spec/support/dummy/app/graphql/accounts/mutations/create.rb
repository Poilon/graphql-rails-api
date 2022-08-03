Accounts::Mutations::Create = GraphQL::Field.define do
  description 'Creates a Account'
  type Accounts::Type

  argument :account, !Accounts::Mutations::InputType

  resolve ApplicationService.call(:account, :create)
end
