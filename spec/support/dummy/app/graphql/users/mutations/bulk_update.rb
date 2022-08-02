Users::Mutations::BulkUpdate = GraphQL::Field.define do
  description 'Updates some Users'
  type types[Users::Type]

  argument :user, !types[Users::Mutations::InputType]

  resolve ApplicationService.call(:user, :bulk_update)
end
