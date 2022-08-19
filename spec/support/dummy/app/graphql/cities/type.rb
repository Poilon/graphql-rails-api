Cities::Type = GraphQL::ObjectType.define do
  name 'City'
  field :id, !types.String
  field :house_ids, types[types.String] do
    resolve CollectionIdsResolver
  end
  field :houses, types[Houses::Type]
  field :created_at, types.String
  field :updated_at, types.String
  field :name, types.String
end
