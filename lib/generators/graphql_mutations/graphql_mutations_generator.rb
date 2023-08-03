class GraphqlMutationsGenerator < Rails::Generators::NamedBase
  def generate
    resource = file_name.underscore.singularize
    dir = "app/graphql/#{resource.pluralize}/mutations"
    FileUtils.mkdir_p(dir) unless File.directory?(dir)
    generate_create_mutation(dir, resource)
    generate_update_mutation(dir, resource)
    generate_destroy_mutation(dir, resource)
  end

  private

  def generate_create_mutation(dir, resource)
      File.write(
      "#{dir}/create.rb",
      <<~STRING
        module #{resource_class(resource)}
          module Mutations
            class Create < GraphQL::Schema::Mutation
              graphql_name "Create#{resource_class(resource)}"
              description "Create a #{resource_class(resource).singularize}"
              field :errors, [String], null: true
              field :#{resource}, #{resource_class(resource)}::Type, null: true
              argument :attributes, #{resource_class(resource)}::Mutations::InputType, required: false
              def resolve(attributes:)
                ApplicationService.call(:#{resource}, :create, context, attributes)
              end
            end
          end
        end
      STRING
      )
  end

  def generate_update_mutation(dir, resource)
      File.write(
      "#{dir}/update.rb",
      <<~STRING
        module #{resource_class(resource)}
          module Mutations
            class Update < GraphQL::Schema::Mutation
              graphql_name "Update#{resource_class(resource)}"
              description "Update a #{resource_class(resource).singularize}"
              field :errors, [String], null: true
              field :#{resource}, #{resource_class(resource)}::Type, null: true
              argument :id, String, required: true
              argument :attributes, #{resource_class(resource)}::Mutations::InputType, required: false
              def resolve(id:, attributes:)
                ApplicationService.call(:#{resource}, :update, context, id, attributes)
              end
            end
          end
        end
      STRING
      )
  end

  def generate_destroy_mutation(dir, resource)
      File.write(
      "#{dir}/destroy.rb",
      <<~STRING
        module #{resource_class(resource)}
          module Mutations
            class Destroy < GraphQL::Schema::Mutation
              graphql_name "Destroy#{resource_class(resource)}"
              description "Destroy a #{resource_class(resource).singularize}"
              field :errors, [String], null: true
              field :#{resource}, #{resource_class(resource)}::Type, null: true
              argument :id, String, required: true
              def resolve(id:)
                ApplicationService.call(:#{resource}, :destroy, context, id)
              end
            end
          end
        end
      STRING
      )
  end

  def resource_class(resource)
    @resource_class ||= resource.pluralize.camelize
  end
end