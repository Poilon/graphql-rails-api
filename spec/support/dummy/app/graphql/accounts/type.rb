Accounts::Type = GraphQL::ObjectType.define do
  name 'Account'
  field :id, !types.String
  field :created_at, types.String
  field :updated_at, types.String
  field :user_id, types.String
  field :user, Users::Type
end
