class GraphqlMutationsGenerator < Rails::Generators::NamedBase

  def generate
    resource = file_name.underscore.singularize
    dir = "app/graphql/#{resource.pluralize}/mutations"
    FileUtils.mkdir_p(dir) unless File.directory?(dir)
    generate_create_mutation(dir, resource)
    generate_update_mutation(dir, resource)
    generate_destroy_mutation(dir, resource)
    generate_bulk_create_mutation(dir, resource)
    generate_bulk_update_mutation(dir, resource)
  end

  private

  def generate_bulk_create_mutation(dir, resource)
    File.write(
      "#{dir}/bulk_create.rb",
      <<~STRING
        #{resource_class(resource)}::Mutations::BulkCreate = GraphQL::Field.define do
          description 'creates some #{resource_class(resource).pluralize}'
          type types[#{resource_class(resource)}::Type]

          argument :#{resource}, !types[#{resource_class(resource)}::Mutations::InputType]

          resolve ApplicationService.call(:#{resource}, :bulk_create)
        end
      STRING
    )
  end

  def generate_bulk_update_mutation(dir, resource)
    File.write(
      "#{dir}/bulk_update.rb",
      <<~STRING
        #{resource_class(resource)}::Mutations::BulkUpdate = GraphQL::Field.define do
          description 'Updates some #{resource_class(resource).pluralize}'
          type types[#{resource_class(resource)}::Type]

          argument :#{resource}, !types[#{resource_class(resource)}::Mutations::InputType]

          resolve ApplicationService.call(:#{resource}, :bulk_update)
        end
      STRING
    )
  end

  def generate_create_mutation(dir, resource)
    File.write(
      "#{dir}/create.rb",
      <<~STRING
        #{resource_class(resource)}::Mutations::Create = GraphQL::Field.define do
          description 'Creates a #{resource_class(resource).singularize}'
          type #{resource_class(resource)}::Type

          argument :#{resource}, !#{resource_class(resource)}::Mutations::InputType

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

          argument :id, types.String
          argument :#{resource}, !#{resource_class(resource)}::Mutations::InputType

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

          argument :id, !types.String

          resolve ApplicationService.call(:#{resource}, :destroy)
        end
      STRING
    )
  end

  def resource_class(resource)
    @resource_class ||= resource.pluralize.camelize
  end

end
