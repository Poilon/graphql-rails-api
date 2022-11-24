require "graphql/rails/api/config"

module GraphqlRailsApi
  class InstallGenerator < Rails::Generators::Base
    class_option("generate_graphql_route", type: :boolean, default: true)

    def generate_files
      @app_name = File.basename(Rails.root.to_s).underscore

      folder = "app/graphql/"
      FileUtils.mkdir_p(folder) unless File.directory?(folder)

      write_uuid_extensions_migration

      write_service
      write_schema
      write_query_type
      write_mutation_type
      write_collection_ids_resolver

      write_controller

      system "rails g graphql_resource user first_name:string last_name:string email:string"

      write_application_record_methods
      write_initializer
      write_require_application_rb

      write_route if options.generate_graphql_route?
    end

    private

    def write_route
      route_file = File.read("config/routes.rb")
      return if route_file.include?("graphql")

      File.write(
        "config/routes.rb",
        route_file.gsub(
          "Rails.application.routes.draw do\n",
          "Rails.application.routes.draw do\n" \
          "  post '/graphql', to: 'graphql#execute'\n"
        )
      )
    end

    def write_collection_ids_resolver
      File.write(
        "app/graphql/collection_ids_resolver.rb",
        <<~STRING
          class CollectionIdsResolver

            def self.call(obj, _args, ctx)
              if obj.is_a?(OpenStruct)
                obj[ctx.field.name.gsub('_ids', '').pluralize]&.map(&:id)
              else
                obj.send(ctx.field.name)
              end
            end

          end
        STRING
      )
    end

    def write_application_record_methods
      lines_count = File.read("app/models/application_record.rb").lines.count

      return if File.read("app/models/application_record.rb").include?("def self.visible_for")
      write_at(
        "app/models/application_record.rb",
        lines_count,
        <<-STRING
  def self.visible_for(*)
    all
  end

  def self.writable_by(*)
    all
  end


        STRING
      )
    end

    def write_require_application_rb
      write_at("config/application.rb", 5, "require 'graphql/hydrate_query'\nrequire 'rkelly'\nrequire 'graphql'\n")
    end

    def write_uuid_extensions_migration
      system("bundle exec rails generate migration uuid_pg_extensions --skip")
      migration_file = Dir.glob("db/migrate/*uuid_pg_extensions*").last
      File.write(
        migration_file,
        <<~STRING
          class UuidPgExtensions < ActiveRecord::Migration[5.2]

            def change
              enable_extension 'pgcrypto'
            end

          end
        STRING
      )
    end

    def write_initializer
      File.write(
        "config/initializers/graphql_rails_api_config.rb",
        <<~STRING
          require 'graphql/rails/api/config'

          config = Graphql::Rails::Api::Config.instance
        STRING
      )
    end

    def write_controller
      File.write(
        "app/controllers/graphql_controller.rb",
        <<~STRING
          class GraphqlController < ApplicationController

            # GraphQL endpoint
            def execute
              result = #{@app_name.camelize}Schema.execute(
                params[:query],
                variables: ensure_hash(params[:variables]),
                context: { current_user: authenticated_user },
                operation_name: params[:operationName]
              )
              render json: result
            end

            private

            def authenticated_user
              # Here you need to authenticate the user.
            end

            # Handle form data, JSON body, or a blank value
            def ensure_hash(ambiguous_param)
              case ambiguous_param
              when String
                ambiguous_param.present? ? ensure_hash(JSON.parse(ambiguous_param)) : {}
              when Hash, ActionController::Parameters
                ambiguous_param
              when nil
                {}
              else
                raise ArgumentError, 'Unexpected parameter: ' + ambiguous_param
              end
            end

          end
        STRING
      )
    end

    def write_mutation_type
      File.write(
        "app/graphql/mutation_type.rb",
        <<~'STRING'
          class MutationType < GraphQL::Schema::Object
            graphql_name "Mutation"
            description "The mutation root of this schema"

            Graphql::Rails::Api::Config.mutation_resources.each do |methd, resources|
              resources.each do |resource|
                field(
                  "#{methd}_#{resource.singularize}".to_sym,
                  mutation: "#{resource.camelize}::Mutations::#{methd.camelize}".constantize
                )
              end
            end
          end
        STRING
      )
    end

    def write_query_type
      File.write(
        "app/graphql/query_type.rb",
        <<~'STRING'
          class QueryType < GraphQL::Schema::Object
            description "The query root of this schema"

            Graphql::Rails::Api::Config.query_resources.each do |resource|
              klass = Class.new(GraphQL::Schema::Object) do
                graphql_name "Paginated#{resource.classify}"

                field :total_count, Integer, null: false
                field :page, Integer, null: false
                field :per_page, Integer, null: false
                field :data, ["#{resource.pluralize.camelize}::Type".constantize], null: false
              end

              resource.pluralize.camelize.constantize.const_set(
                :PaginatedType,
                klass
              )

              field "paginated_#{resource.pluralize}", "#{resource.camelize}::PaginatedType".constantize, null: false do
                description "Return paginated #{resource.classify}"
                argument :page, Integer, required: true
                argument :per_page, Integer, required: true
                argument :filter, String, required: false
                argument :order_by, type: String, required: false
              end

              define_method("paginated_#{resource.pluralize}") do |page:, per_page:, filter: nil, order_by: nil|
                arguments = {
                  page: page,
                  per_page: per_page,
                  filter: filter,
                  order_by: order_by
                }
                ApplicationService.call(resource, :paginated_index, context, arguments)
              end

              field resource.pluralize.to_sym, ["#{resource.camelize}::Type".constantize], null: false do
                description "All #{resource.pluralize}"
                argument :page, Integer, required: false
                argument :per_page, Integer, required: false
                argument :filter, String, required: false
                argument :order_by, String, required: false
              end

              define_method(resource.pluralize) do |page: nil, per_page: nil, filter: nil, order_by: nil|
                arguments = {page: page, per_page: per_page, filter: filter, order_by: order_by}
                ApplicationService.call(resource, :index, context, arguments)
              end

              field resource.singularize.to_sym, "#{resource.camelize}::Type".constantize, null: false do
                description "A #{resource.singularize}"
                argument :id, String, required: true
              end

              define_method(resource.singularize) do |id:|
                arguments = {id: id}
                ApplicationService.call(resource, :show, context, arguments)
              end
            end
          end

        STRING
      )
    end

    def write_schema
      logger = <<~'STRING'
        type_error_logger = Logger.new("#{Rails.root}/log/graphql_type_errors.log")
      STRING

      error_handler = <<~'STRING'
        type_error_logger.error "#{err} for #{query_ctx.query.query_string} \
            with #{query_ctx.query.provided_variables}"
      STRING

      File.write(
        "app/graphql/#{@app_name}_schema.rb",
        <<~STRING
                class #{@app_name.camelize}Schema < GraphQL::Schema
                  query QueryType
                  mutation MutationType
                  max_depth 15

                  def self.type_error(err, query_ctx)
                    type_error_logger = Logger.new("#{Rails.root}/log/graphql_type_errors.log")

                    type_error_logger.error(
                      "#{err} for #{query_ctx.query.query_string} with #{query_ctx.query.provided_variables}"
                    )
                  end
                end
              <<~STRING
            )
          end

          def write_service
            File.write(
              'app/graphql/application_service.rb',
              <<~'STRING'
                class ApplicationService

                  attr_accessor :params, :object, :fields, :user

                  def initialize(params: {}, object: nil, object_id: nil, user: nil, context: nil)
                    @params = params.is_a?(Array) ? params.map { |p| p.to_h.symbolize_keys } : params.to_h.symbolize_keys
                    @context = context
                    @object = object || (object_id && model.visible_for(user: user).find_by(id: object_id))
                    @object_id = object_id
                    @user = user
                  end

                  def self.call(resource, meth)
                    lambda { |_obj, args, context|
                      params = args && args[resource] ? args[resource] : args
                      "#{resource.to_s.pluralize.camelize.constantize}::Service".constantize.new(
                        params: params, user: context[:current_user],
                        object_id: args[:id], context: context
                      ).send(meth)
                    }
                  end

                  def index
                    Graphql::HydrateQuery.new(
                      model.all,
                      @context,
                      order_by: params[:order_by],
                      filter: params[:filter],
                      per_page: params[:per_page],
                      page: params[:page],
                      user: user
                    ).run.compact
                  end

                  def show
                    object = Graphql::HydrateQuery.new(model.all, @context, user: user, id: params[:id]).run
                    return not_allowed if object.blank?

                    object
                  end

                  def create
                    object = model.new(params.select { |p| model.new.respond_to?(p) })
                    return not_allowed if not_allowed_to_create_resource(object)

                    if object.save
                      { singular_resource => Graphql::HydrateQuery.new(model.all, @context, user: user, id: object.id).run }
                    else
                      graphql_error(object.errors.full_messages.join(', '))
                    end
                  end

                  def update
                    return not_allowed if write_not_allowed

                    if object.update_attributes(params)
                      { singular_resource => Graphql::HydrateQuery.new(model.all, @context, user: user, id: object.id).run }
                    else
                      graphql_error(object.errors.full_messages.join(', '))
                    end
                  end

                  def destroy
                    object = model.find_by(id: params[:id])
                    return not_allowed if write_not_allowed

                    if object.destroy
                      { singular_resource => object.attributes }
                    else
                      graphql_error(object.errors.full_messages.join(', '))
                    end
                  end

                  private

                  def write_not_allowed
                    !model.visible_for(user: user).include?(object) if object
                  end

                  def access_not_allowed
                    !model.visible_for(user: user).include?(object) if object
                  end

                  def not_allowed
                    graphql_error('403 - Not allowed')
                  end

                  def graphql_error(message)
                    GraphQL::ExecutionError.new(message)
                  end

                  def singular_resource
                    resource_name.singularize
                  end

                  def model
                    singular_resource.camelize.constantize
                  end

                  def resource_name
                    self.class.to_s.split(':').first.underscore
                  end

                  def not_allowed_to_create_resource(created_resource)
                    params.select { |k, _| k.to_s.end_with?('_id') }.each do |belongs_relation, rel_id|
                      klass = created_resource.class.reflect_on_association(belongs_relation.to_s.gsub('_id', '')).klass
                      return true if rel_id.present? && !klass.visible_for(user: user).pluck(:id).include?(rel_id)
                    end

                    params.select { |k, _| k.to_s.end_with?('_ids') }.each do |many_relation, rel_ids|
                      klass = created_resource.class.reflect_on_association(many_relation.to_s.gsub('_ids', '').pluralize).klass
                      ids = klass.visible_for(user: user).pluck(:id)
                      rel_ids.each { |id| return true if id.present? && !ids.include?(id) }
                    end
                    false
                  end

                end

        STRING
      )
    end

    def write_at(file_name, line, data)
      open(file_name, "r+") do |f|
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
end
