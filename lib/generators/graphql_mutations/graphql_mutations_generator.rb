class GraphqlMutationsGenerator < Rails::Generators::NamedBase

  def generate
    @id = Graphql::Rails::Api::Config.instance.id_type == :uuid ? '!types.String' : '!types.ID'
    resource = file_name.underscore.singularize
    dir = "app/graphql/#{resource.pluralize}/mutations"
    system("mkdir -p #{dir}")
    generate_create_mutation(dir, resource)
    generate_update_mutation(dir, resource)
    generate_destroy_mutation(dir, resource)
  end

  private

  def generate_create_mutation(dir, resource)
    File.write(
      "#{dir}/create.rb",
      <<~STRING
        #{resource_class(resource)}::Mutations::Create = GraphQL::Field.define do
          description 'Creates a #{resource_class(resource).singularize}'
          type #{resource_class(resource)}::Type

          argument :#{resource}, #{resource_class(resource)}::Mutations::InputType

          resolve ApplicationService.call(:#{resource}, :create)
        end
      STRING
    )
  end

  def generate_update_mutation(dir, resource)
    File.write(
      "#{dir}/update.rb",
      <<~STRING
        #{resource_class(resource)}::Mutations::Update = GraphQL::Field.define do
          description 'Updates a #{resource_class(resource).singularize}'
          type #{resource_class(resource)}::Type

          argument :id, #{@id}
          argument :#{resource}, #{resource_class(resource)}::Mutations::InputType

          resolve ApplicationService.call(:#{resource}, :update)
        end
      STRING
    )
  end

  def generate_destroy_mutation(dir, resource)
    File.write(
      "#{dir}/destroy.rb",
      <<~STRING
        #{resource_class(resource)}::Mutations::Destroy = GraphQL::Field.define do
          description 'Destroys a #{resource_class(resource).singularize}'
          type #{resource_class(resource)}::Type

          argument :id, #{@id}

          resolve ApplicationService.call(:#{resource}, :destroy)
        end
      STRING
    )
  end

  def resource_class(resource)
    @resource_class ||= resource.pluralize.camelize
  end

end
