class GraphqlBulkCreateMutationsGenerator < Rails::Generators::NamedBase

  def generate
    Graphql::Rails::Api::Config.query_resources.each do |resource|
      dir = "#{Rails.root}/app/graphql/#{resource.pluralize}/mutations"
      generate_bulk_create_mutation(dir, resource) if Dir.exist?(dir)
    end
  end

  def generate_bulk_create_mutation(dir, resource)
    File.write(
      "#{dir}/bulk_create.rb",
      <<~STRING
        #{resource_class(resource)}::Mutations::BulkCreate = GraphQL::Field.define do
          description 'creates some #{resource_class(resource).pluralize}'
          type types[#{resource_class(resource)}::Type]

          argument :#{resource}, types[#{resource_class(resource)}::Mutations::InputType]

          resolve ApplicationService.call(:#{resource}, :bulk_create)
        end
      STRING
    )
  end

  def resource_class(resource)
    resource.pluralize.camelize
  end

end
