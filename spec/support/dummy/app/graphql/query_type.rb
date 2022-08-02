QueryType = GraphQL::ObjectType.define do
  name 'Query'

  Graphql::Rails::Api::Config.query_resources.each do |resource|
    field resource.singularize do
      description "Returns a #{resource.classify}"
      type !"#{resource.camelize}::Type".constantize
      argument :id, !types.String
      resolve ApplicationService.call(resource, :show)
    end

    field resource.pluralize do
      description "Returns a #{resource.classify}"
      type !types[!"#{resource.camelize}::Type".constantize]
      argument :page, types.Int
      argument :per_page, types.Int
      argument :filter, types.String
      argument :order_by, types.String
      resolve ApplicationService.call(resource, :index)
    end

  end

  field :me, Users::Type do
    description 'Returns the current user'
    resolve ->(_, _, ctx) { ctx[:current_user] }
  end

end
