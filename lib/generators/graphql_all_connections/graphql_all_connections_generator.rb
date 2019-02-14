class GraphqlAllConnectionsGenerator < Rails::Generators::NamedBase

  def generate
    Graphql::Rails::Api::Config.query_resources.each do |resource|
      dir = "app/graphql/#{resource.pluralize}"
      generate_connection(dir, resource) if Dir.exist?(dir)
    end
  end

  def generate_connection(dir, resource)
    File.write(
      "#{dir}/connection.rb",
      <<~STRING
        #{resource.pluralize.camelize}::Connection = #{resource.pluralize.camelize}::Type.define_connection do
          name '#{resource.camelize}Connection'

          field :total_count, types.Int do
            resolve ->(obj, _, _) { obj.nodes.count }
          end
        end
      STRING
    )
  end

end
