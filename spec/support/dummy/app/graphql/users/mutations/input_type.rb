Users::Mutations::InputType = GraphQL::InputObjectType.define do
  name 'UserInputType'
  description 'Properties for updating a User'
  argument :websocket_connection_ids, types[types.String]

  argument :first_name, types.String
  argument :last_name, types.String
  argument :email, types.String

end
