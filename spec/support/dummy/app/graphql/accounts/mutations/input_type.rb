Accounts::Mutations::InputType = GraphQL::InputObjectType.define do
  name 'AccountInputType'
  description 'Properties for updating a Account'

  argument :user_id, types.String

end
