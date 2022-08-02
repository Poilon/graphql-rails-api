Houses::Mutations::Destroy = GraphQL::Field.define do
  description 'Destroys a House'
  type Houses::Type

  argument :id, !types.String

  resolve ApplicationService.call(:house, :destroy)
end
