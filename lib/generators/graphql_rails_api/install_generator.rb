require 'graphql/rails/api/config'

module GraphqlRailsApi
  class InstallGenerator < Rails::Generators::Base

    class_option('apollo_compatibility', type: :boolean, default: true)
    class_option('action_cable_subs', type: :boolean, default: true)
    class_option('pg_uuid', type: :boolean, default: true)
    class_option('generate_graphql_route', type: :boolean, default: true)

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
      if options.action_cable_subs?
        write_websocket_connection
        write_online_users_channel
      end
      write_initializer
      write_require_application_rb
      write_route if options.generate_graphql_route?
      write_uuid_extensions_migration if options.pg_uuid?
    end

    private

    def write_route
      route_file = File.read('config/routes.rb')
      return if route_file.include?('graphql')
      File.write(
        'config/routes.rb',
        route_file.gsub(
          "Rails.application.routes.draw do\n",
          "Rails.application.routes.draw do\n  post '/graphql', to: 'graphql#execute'\n"
        )
      )
    end

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
      return unless options.action_cable_subs?

      lines_count = File.read('app/models/application_record.rb').lines.count
      write_at(
        'app/models/application_record.rb',
        lines_count,
        <<-STRING
  after_commit :notify_online_users

  def notify_online_users
    Redis.current.keys('#{Rails.application.class.parent_name.underscore}_subscribed_query_*').each_with_object({}) do |key, hash|
      hash[
        key.gsub('#{Rails.application.class.parent_name.underscore}_subscribed_query_', '')
      ] = Redis.current.hgetall(key).each_with_object([]) do |(data, vars), array|
        data = data.split('/////')
        array << { query: data[0], store: data[1], variables: vars.blank? ? nil : JSON.parse(vars), scope: data[2] }
      end
    end.each do |user_id, user_queries_array|
      user_queries_array.map { |user_hash| notify_user(user_id, user_hash) }
    end
  end

  def notify_user(user_id, user_hash)
    model_name = self.class.to_s.underscore
    if !user_hash[:query].include?(model_name.singularize + '(id: $id') &&
        !user_hash[:query].include?(' ' + model_name.pluralize)
      return
    end
    return if user_hash[:query].include?(model_name + '(id: $id') && user_hash[:variables]['id'] != id

    u = User.find_by(id: user_id)
    return unless u

    result = #{Rails.application.class.parent_name}ApiSchema.execute(user_hash[:query], context: { current_user: u }, variables: user_hash[:variables])
    OnlineUsersChannel.broadcast_to(u, store: user_hash[:store], scope: user_hash[:scope], result: result['data'])
  end

        STRING
      )
    end

    def write_require_application_rb
      write_at(
        'config/application.rb',
        5,
        "require 'graphql/hydrate_query'\n"
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
        STRING
      )
    end

    def write_websocket_connection
      File.write(
        'app/channels/application_cable/connection.rb',
        <<~'STRING'
          module ApplicationCable
            class Connection < ActionCable::Connection::Base

              identified_by :current_user

              def connect
                # Check authentication, and define current user
                self.current_user = nil
              end

            end
          end
        STRING
      )
    end

    def write_online_users_channel
      File.write(
        'app/channels/online_users_channel.rb',
        <<~STRING
          class OnlineUsersChannel < ApplicationCable::Channel

            def subscribed
              stream_for(current_user)
              Redis.current.hset('#{Rails.application.class.parent_name.underscore}_online_users', current_user.id, '1')
              User.online.each do |user|
                OnlineUsersChannel.broadcast_to(user, User.online_user_ids)
              end
            end

            def subscribe_to_query(data)
              Redis.current.hset(
                '#{Rails.application.class.parent_name.underscore}_subscribed_query_' + current_user.id,
                data['query'] + '/////' + data['store'] + '/////' + data['scope'],
                data['variables']
              )
            end

            def unsubscribe_to_query(data)
              Redis.current.hdel(
                '#{Rails.application.class.parent_name.underscore}_subscribed_query_' + current_user.id,
                data['query'] + '/////' + data['store']
              )
            end

            def unsubscribed
              Redis.current.hset('#{Rails.application.class.parent_name.underscore}_online_users', current_user.id, '0')
              Redis.current.hdel('#{Rails.application.class.parent_name.underscore}_subscribed_query_' + current_user.id, current_user.id)
              User.online.each do |user|
                OnlineUsersChannel.broadcast_to(user, User.online_user_ids)
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

              # current_user
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
              HydrateQuery.new(
                model.all,
                @context,
                order_by: params[:order_by],
                filter: params[:filter],
                user: user
              ).run
            end

            def show
              return not_allowed if access_not_allowed

              showed_resource = HydrateQuery.new(model.all, @context, user: user, id: object.id).run

              return not_allowed if showed_resource.blank?

              showed_resource
            end

            def create
              if user&.action?("can_create_#{singular_resource}")
                created_resource = model.new(params.select { |p| model.new.respond_to?(p) })
                return not_allowed if not_allowed_to_create_resource(created_resource)

                created_resource.save ? created_resource : graphql_error(created_resource.errors.full_messages.join(', '))
              elsif user&.action?("can_create_#{singular_resource}_with_verif")
                Verification.create(action: 'create', model: model.to_s, params: params, user_id: user.id)
                graphql_error("Pending verification for a #{singular_resource} creation")
              else
                not_allowed
              end
            end

            def update
              return not_allowed if write_not_allowed

              if user.action?("can_update_#{singular_resource}")
                object.update_attributes(params) ? object : graphql_error(object.errors.full_messages.join(', '))
              elsif user.action?("can_update_#{singular_resource}_with_verif")
                create_update_verification
              else
                not_allowed
              end
            end

            def destroy
              return not_allowed if write_not_allowed || !user.action?("can_delete_#{singular_resource}")

              object.destroy ? object : graphql_error(object.errors.full_messages.join(', '))
            end

            private

            def create_update_verification
              Verification.create(
                action: 'update', model: model.to_s, params: params.merge(id: object.id), user_id: user.id
              )
              graphql_error("Pending verification for a #{singular_resource} update")
            end

            def write_not_allowed
              return true unless object

              !model.writable_for(user: user).pluck(:id).include?(object.id)
            end

            def access_not_allowed
              return true unless object

              !model.visible_for(user: user).pluck(:id).include?(object.id)
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
