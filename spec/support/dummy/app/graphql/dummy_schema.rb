type_error_logger = Logger.new("#{Rails.root}/log/graphql_type_errors.log")

# /!\ do not remove /!\
# Apollo Data compat.
ClientDirective = GraphQL::Directive.define do
  name 'client'
  locations([GraphQL::Directive::FIELD])
  default_directive true
end
ConnectionDirective = GraphQL::Directive.define do
  name 'connection'
  locations([GraphQL::Directive::FIELD])
  argument :key, GraphQL::STRING_TYPE
  argument :filter, GraphQL::STRING_TYPE.to_list_type
  default_directive true
end
# end of Apollo Data compat.

# Schema definition
DummySchema = GraphQL::Schema.define do
  mutation(MutationType)
  query(QueryType)
  directives [ConnectionDirective, ClientDirective]
  type_error lambda { |err, query_ctx|
    type_error_logger.error "#{err} for #{query_ctx.query.query_string} \
    with #{query_ctx.query.provided_variables}"
  }
end
