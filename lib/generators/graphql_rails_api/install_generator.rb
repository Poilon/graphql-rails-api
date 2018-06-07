require 'graphql/rails/api/config'

module GraphqlRailsApi
  class InstallGenerator < Rails::Generators::Base

    class_option('apollo_compatibility', type: :boolean, default: true)
    class_option('action_cable_subs', type: :boolean, default: true)
    class_option('pg_uuid', type: :boolean, default: true)

    def generate_files
      @app_name = File.basename(Rails.root.to_s).underscore
      system('mkdir -p app/graphql/')

      write_service
      write_application_record_methods
      write_schema
      write_query_type
      write_mutation_type
      write_subscription_type
      write_controller
      write_channel if options.action_cable_subs?
      write_initializer
      write_require_application_rb
      write_uuid_extensions_migration if options.pg_uuid?
    end

    private

    def write_application_record_methods
      lines_count = File.read('app/models/application_record.rb').lines.count

      return if File.read('app/models/application_record.rb').include?('def self.visible_for')
      write_at(
        'app/models/application_record.rb',
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
      File.write(
        'config/application.rb',
        File.read('config/application.rb').gsub(
          "require 'rails/all'",
          "require 'rails/all'\nrequire 'graphql/hydrate_query'\n"
        )
      )
    end

    def write_uuid_extensions_migration
      system('bundle exec rails generate migration uuid_pg_extensions --skip')
      migration_file = Dir.glob('db/migrate/*uuid_pg_extensions*').last
      File.write(
        migration_file,
        <<~STRING
          class UuidPgExtensions < ActiveRecord::Migration[5.1]

            def change
              execute 'CREATE EXTENSION "pgcrypto" SCHEMA pg_catalog;'
              execute 'CREATE EXTENSION "uuid-ossp" SCHEMA pg_catalog;'
            end

          end
        STRING
      )
    end

    def write_initializer
      File.write(
        'config/initializers/graphql_rails_api_config.rb',
        <<~STRING
          require 'graphql/rails/api/config'

          config = Graphql::Rails::Api::Config.instance

          config.id_type = #{options.pg_uuid? ? ':uuid' : ':id'} # :id or :uuid

          # Possibilites are :create, :update or :destroy
          config.basic_mutations = %i[create update destroy]
        STRING
      )
    end

    def write_channel
      File.write(
        'app/channels/graphql_channel.rb',
        <<~STRING
          class GraphqlChannel < ApplicationCable::Channel

            def subscribed
              @subscription_ids = []
            end

            # see graphql-ruby from details
            def execute(data)
              query, context, variables, operation_name = options_for_execute(data)
              result = #{@app_name.camelize}Schema.execute(query: query, context: context,
                                              variables: variables, operation_name: operation_name)
              payload = { result: result.subscription? ? nil : result.to_h, more: result.subscription?,
                          errors: result ? result.to_h[:errors] : nil }
              @subscription_ids << result.context[:subscription_id] if result.context[:subscription_id]
              transmit(payload)
            end

            def unsubscribed
              @subscription_ids.each do |sid|
                #{@app_name.camelize}Schema.subscriptions.delete_subscription(sid)
              end
            end

            def options_for_execute(data)
              query = data['query']
              variables = ensure_hash(data['variables'])
              operation_name = data['operationName']
              context = { current_user: current_user, channel: self }.
                        merge(ensure_hash(data['context']).symbolize_keys). # ensure context is filled
                        merge(variables) # include variables in context too
              [query, context, variables, operation_name]
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

    def write_controller
      File.write(
        'app/controllers/graphql_controller.rb',
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
              # You can use devise, then just write:
              current_user
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

    def write_subscription_type
      File.write(
        'app/graphql/subscription_type.rb',
        <<~STRING
          SubscriptionType = GraphQL::ObjectType.define do
            name 'Subscription'
          end
        STRING
      )
    end

    def write_mutation_type
      File.write(
        'app/graphql/mutation_type.rb',
        <<~'STRING'
          MutationType = GraphQL::ObjectType.define do
            name 'Mutation'

            Graphql::Rails::Api::Config.mutation_resources.each do |methd, resources|
              resources.each do |resource|
                field(
                  "#{methd}_#{resource.singularize}".to_sym,
                  "#{resource.camelize}::Mutations::#{methd.camelize}".constantize
                )
              end
            end

          end
        STRING
      )
    end

    def write_query_type
      File.write(
        'app/graphql/query_type.rb',
        <<~'STRING'
          QueryType = GraphQL::ObjectType.define do
            name 'Query'

            Graphql::Rails::Api::Config.query_resources.each do |resource|
              field resource.singularize do
                description "Return a #{resource.classify}"
                type !"#{resource.camelize}::Type".constantize
                argument :id, !types.String
                resolve ApplicationService.call(resource, :show)
              end

              field resource.pluralize do
                description "Return a #{resource.classify}"
                type !types[!"#{resource.camelize}::Type".constantize]
                argument :page, types.Int
                argument :per_page, types.Int
                resolve ApplicationService.call(resource, :index)
              end

            end

          end
        STRING
      )
    end

    def apollo_compat
      <<~'STRING'
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
      STRING
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
          #{logger}
          #{apollo_compat if options.apollo_compatibility?}
          # Schema definition
          #{@app_name.camelize}Schema = GraphQL::Schema.define do
            mutation(MutationType)
            query(QueryType)
            #{'directives [ConnectionDirective, ClientDirective]' if options.apollo_compatibility?}
            #{'use GraphQL::Subscriptions::ActionCableSubscriptions' if options.action_cable_subs?}
            subscription(SubscriptionType)
            type_error lambda { |err, query_ctx|
              #{error_handler}
            }
          end
        STRING
      )
    end

    def write_service
      File.write(
        'app/graphql/application_service.rb',
        <<~'STRING'
          class ApplicationService

            attr_accessor :params, :object, :fields, :user

            def initialize(params: {}, object: nil, object_id: nil, user: nil, context: nil)
              @params = params.to_h.symbolize_keys
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
              Graphql::HydrateGraphqlQuery.new(model.all, @context, user: user).run
            end

            def show
              object = Graphql::HydrateQuery.new(model.all, @context, user: user, id: params[:id]).run
              return not_allowed if object.blank?
              object
            end

            def create
              object = model.new(params.select { |p| model.new.respond_to?(p) })
              if object.save
                object
              else
                graphql_error(object.errors.full_messages.join(', '))
              end
            end

            def destroy
              object = model.find_by(id: params[:id])
              return not_allowed if write_not_allowed
              if object.destroy
                object
              else
                graphql_error(object.errors.full_messages.join(', '))
              end
            end

            def update
              return not_allowed if write_not_allowed
              if object.update_attributes(params)
                object
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

          end

        STRING
      )
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
end
