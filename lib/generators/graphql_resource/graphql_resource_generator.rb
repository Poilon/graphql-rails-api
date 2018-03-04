require 'pry'

class GraphqlResourceGenerator < Rails::Generators::NamedBase

  %i[migration model mutations service graphql_input_type graphql_type propagation migrate].each do |opt|
    class_option(opt, type: :boolean, default: true)
  end

  TYPES_MAPPING = {
    'id' => '!types.ID',
    'uuid' => '!types.String',
    'text' => 'types.String',
    'datetime' => 'types.String',
    'integer' => 'types.Int',
    'json' => 'types.String',
    'jsonb' => 'types.String',
    'string' => 'types.String',
    'float' => 'types.Float'
  }.freeze

  def create_graphql_files
    return if args.blank?
    parse_args

    # Generate migration
    generate_migration if options.migration?

    # Graphql Basic mutations
    generate_basic_mutations if options.mutations?

    # Graphql Type
    generate_graphql_type if options.graphql_type?

    # Model
    generate_model if options.model?

    # Graphql Input Type
    generate_graphql_input_type if options.graphql_input_type?

    # Service
    generate_service if options.service?

    # Propagation
    add_has_many_to_models if options.propagation?
    add_has_many_fields_to_types if options.propagation?
    handle_many_to_many_fields if options.propagation?

    system('bundle exec rails db:migrate') if options.migrate?
  end

  private

  def parse_args
    @graphql_resource_directory = "app/graphql/#{resource.pluralize}"
    @mutations_directory = "#{@graphql_resource_directory}/mutations"

    if Graphql::Rails::Api::Config.instance.id_type == :uuid
      @id_db_type = 'uuid'
      @id_type = '!types.String'
    else
      @id_db_type = 'integer'
      @id_type = '!types.ID'
    end

    @has_many = []
    @many_to_many = []

    @args = args.each_with_object({}) do |f, hash|
      next if f.split(':').count != 2
      case f.split(':').first
      when 'belongs_to' then hash["#{f.split(':').last.singularize}_id"] = "#{@id_db_type}"
      when 'has_many' then @has_many << f.split(':').last.pluralize
      when 'many_to_many' then @many_to_many << f.split(':').last.pluralize
      else
        hash[f.split(':').first] = f.split(':').last
      end
    end

    @id_fields = @args.select { |k, v| k.end_with?('_id') }

    @fields_to_migration = @args.map do |f|
      "t.#{f.reverse.join(' :')}"
    end.join("\n      ")
  end

  def generate_migration
    system("bundle exec rails generate migration create_#{resource} --skip")
    migration_file = Dir.glob("db/migrate/*create_#{resource}*").last
    File.write(
      migration_file,
      <<~STRING
        class Create#{resource.camelize} < ActiveRecord::Migration[5.1]
          def change
            create_table :#{resource.pluralize}, #{'id: :uuid ' if Graphql::Rails::Api::Config.instance.id_type == :uuid}do |t|
              #{@fields_to_migration}
              t.timestamps
            end
          end
        end
      STRING
    )
  end

  def generate_basic_mutations
    system("mkdir -p #{@mutations_directory}")
    generate_create_mutation
    generate_update_mutation
    generate_destroy_mutation
  end

  def generate_create_mutation
    File.write(
      "#{@mutations_directory}/create.rb",
      <<~STRING
        #{resource_class}::Mutations::Create = GraphQL::Field.define do
          description 'Creates a #{resource_class.singularize}'
          type #{resource_class}::Type

          argument :#{resource}, #{resource_class}::Mutations::InputType

          resolve ApplicationService.call(:#{resource}, :create)
        end
      STRING
    )
  end

  def generate_update_mutation
    File.write(
      "#{@mutations_directory}/update.rb",
      <<~STRING
        #{resource_class}::Mutations::Update = GraphQL::Field.define do
          description 'Updates a #{resource_class.singularize}'
          type #{resource_class}::Type

          argument :id, #{@id_type}
          argument :#{resource}, #{resource_class}::Mutations::InputType

          resolve ApplicationService.call(:#{resource}, :update)
        end
      STRING
    )
  end

  def generate_destroy_mutation
    File.write(
      "#{@mutations_directory}/destroy.rb",
      <<~STRING
        #{resource_class}::Mutations::Destroy = GraphQL::Field.define do
          description 'Destroys a #{resource_class.singularize}'
          type #{resource_class}::Type

          argument :id, #{@id_type}

          resolve ApplicationService.call(:#{resource}, :destroy)
        end
      STRING
    )
  end

  def generate_graphql_input_type
    system("mkdir -p #{@mutations_directory}")
    File.write(
      "#{@mutations_directory}/input_type.rb",
      <<~STRING
        #{resource_class}::Mutations::InputType = GraphQL::InputObjectType.define do
          name '#{resource_class.singularize}InputType'
          description 'Properties for updating a #{resource_class.singularize}'

          #{map_types(input_type: true)}

        end
      STRING
    )
  end

  def generate_graphql_type
    File.write(
      "#{@graphql_resource_directory}/type.rb",
      <<~STRING
        #{resource_class}::Type = GraphQL::ObjectType.define do
          name '#{resource_class.singularize}'
          field :id, #{@id_type}
          field :created_at, types.String
          field :updated_at, types.String
          #{map_types(input_type: false)}
        end
      STRING
    )
  end

  def generate_model
    belongs_to = generate_belongs_to
    if belongs_to.blank?
      generate_empty_model
    else
      generate_model_with_belongs_to(belongs_to)
    end
  end

  def add_has_many_fields_to_type(field, res)
      file_name = "app/graphql/#{field.pluralize}/type.rb"
      if File.read(file_name).include?("field :#{res.singularize}_ids") ||
          File.read(file_name).include?("field :#{res.pluralize}")
        return
      end
      write_at(
        file_name, 4,
        <<-STRING
  field :#{res.singularize}_ids, !types[#{@id_type}] do
    resolve ->(obj, _, ctx) { obj.#{res.pluralize}.visible_for(user: ctx[:current_user]).pluck(:id) }
  end
  field :#{res.pluralize}, !types[!#{res.pluralize.camelize}::Type] do
    resolve ->(obj, _, ctx) { obj.#{res.pluralize}.visible_for(user: ctx[:current_user]) }
  end
        STRING
      )
  end

  def add_belongs_to_field_to_type(field, res)
    file_name = "app/graphql/#{res.pluralize}/type.rb"
    if File.read(file_name).include?("field :#{field.singularize}_id") ||
        File.read(file_name).include?("field :#{field.singularize}")
      return
    end
    write_at(
      file_name, 4,
      <<-STRING
  field :#{field.singularize}_id, !types[#{@id_type}]
  field :#{field.singularize}, !#{field.pluralize.camelize}::Type
      STRING
    )
  end
  
  def add_has_many_fields_to_types
    @has_many.each do |f|
      add_has_many_fields_to_type(resource, f)
      add_belongs_to_field_to_type(resource, f)
    end
    @id_fields.each do |f, _|
      add_has_many_fields_to_type(f.gsub('_id', ''), resource)
      add_belongs_to_field_to_type(f.gsub('_id', ''), resource)
    end
  end

  def handle_many_to_many_fields
    @many_to_many.each do |field|

    end
  end


  def generate_model_with_belongs_to(belongs_to)
    File.write(
      "app/models/#{resource}.rb",
      <<~STRING
        class #{resource.camelize} < ApplicationRecord

          #{belongs_to}
        end
      STRING
    )
  end

  def generate_empty_model
    File.write(
      "app/models/#{resource}.rb",
      <<~STRING
        class #{resource.camelize} < ApplicationRecord

        end
      STRING
    )
  end

  def generate_service
    File.write(
      "app/graphql/#{resource.pluralize}/service.rb",
      <<~STRING
        module #{resource.pluralize.camelize}
          class Service < ApplicationService

          end
        end
      STRING
    )
  end

  def generate_has_many_migration(f)
    system("bundle exec rails generate migration add_#{resource.singularize}_id_to_#{f} --skip")
    migration_file = Dir.glob("db/migrate/*add_#{resource.singularize}_id_to_#{f}*").last
    File.write(
      migration_file,
      <<~STRING
        class Add#{resource.singularize.camelize}IdTo#{f.camelize} < ActiveRecord::Migration[5.1]
          def change
            add_column :#{f.pluralize}, :#{resource.singularize}_id, :#{@id_db_type}
          end
        end
      STRING
    )
  end

  def add_has_many_to_models
    @has_many.each do |f|
      next unless File.exist?("app/models/#{resource.singularize}.rb")
      next unless File.exist?("app/models/#{f.singularize}.rb")
      unless File.read("app/models/#{resource.singularize}.rb").include?("has_many :#{f.pluralize}")
        write_at("app/models/#{resource.singularize}.rb", 3, "  has_many :#{f.pluralize}\n")
      end
      unless File.read("app/models/#{f.singularize}.rb").include?("belongs_to :#{resource.singularize}")
        write_at("app/models/#{f.singularize}.rb", 3, "  belongs_to :#{resource.singularize}\n")
      end
      if !f.singularize.camelize.constantize.new.respond_to?("#{resource.singularize}_id")
        generate_has_many_migration(f)
      end
    end
    @id_fields.each do |k, v|
      next unless File.exist?("app/models/#{k.gsub('_id', '').singularize}.rb")
      next if File.read("app/models/#{k.gsub('_id', '').singularize}.rb").include?("has_many :#{resource.pluralize}")
      write_at(
        "app/models/#{k.gsub('_id', '').singularize}.rb", 3, "  has_many :#{resource.pluralize}\n"
      )
    end
  end

  def generate_belongs_to
    @id_fields.map do |k, _|
      "belongs_to :#{k.gsub('_id', '')}"
    end.join("\n  ") + "\n"
  end

  def map_types(input_type: false)
    result = args&.map do |k, v|
      field_name = k
      field_type = TYPES_MAPPING[v]
      res = "#{input_type ? 'argument' : 'field'} :#{field_name}, #{field_type}"
      if !input_type && field_name.ends_with?('_id')
        res += "\n  field :#{field_name.gsub('_id', '')}, " \
          "!#{field_name.gsub('_id', '').pluralize.camelize}::Type"
      end
      res
    end&.join("\n  ")
    input_type ? result.gsub("field :id, #{@id_type}\n", '') : result
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

  def resource
    @_resource ||= file_name.singularize.downcase
  end

  def resource_class
    @_resource_class ||= resource.pluralize.camelize
  end

end
