Users::Mutations::BulkCreate = GraphQL::Field.define do
  description 'creates some Users'
  type types[Users::Type]

  argument :user, !types[Users::Mutations::InputType]

  resolve ApplicationService.call(:user, :bulk_create)
end
