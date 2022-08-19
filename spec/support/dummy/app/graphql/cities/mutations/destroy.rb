Cities::Mutations::Destroy = GraphQL::Field.define do
  description 'Destroys a City'
  type Cities::Type

  argument :id, !types.String

  resolve ApplicationService.call(:city, :destroy)
end
