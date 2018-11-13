class GraphqlBulkUpdateMutationsGenerator < Rails::Generators::NamedBase

  def generate
    Graphql::Rails::Api::Config.query_resources.each do |resource|
      dir = "#{Rails.root}/app/graphql/#{resource.pluralize}/mutations"
      generate_bulk_update_mutation(dir, resource) if Dir.exist?(dir)
    end
  end

  def generate_bulk_update_mutation(dir, resource)
    File.write(
      "#{dir}/bulk_update.rb",
      <<~STRING
        #{resource_class(resource)}::Mutations::BulkUpdate = GraphQL::Field.define do
          description 'Updates some #{resource_class(resource).pluralize}'
          type types[#{resource_class(resource)}::Type]

          argument :#{resource}, types[#{resource_class(resource)}::Mutations::InputType]

          resolve ApplicationService.call(:#{resource}, :bulk_update)
        end
      STRING
    )
  end

  def resource_class(resource)
    resource.pluralize.camelize
  end

  def write_at(file_name, line, data)
    open(file_name, 'r+') do |f|
      while (line -= 1).positive?
        f.readline
      end
      pos = f.pos
      rest = f.read
      f.seek pos
      f.write data
      f.write rest
    end
  end

end
