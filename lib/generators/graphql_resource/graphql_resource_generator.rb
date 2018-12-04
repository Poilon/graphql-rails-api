class GraphqlResourceGenerator < Rails::Generators::NamedBase

  %i[
    migration model mutations service graphql_input_type
    graphql_type propagation connection migrate
  ].each do |opt|
    class_option(opt, type: :boolean, default: true)
  end

  TYPES_MAPPING = {
    'id' => 'types.ID',
    'uuid' => 'types.String',
    'boolean' => 'types.Boolean',
    'float' => 'types.Float',
    'decimal' => 'types.Float',
    'integer' => 'types.Int',
    'bigint' => 'types.Int'
  }.freeze

  def create_graphql_files
    return if args.blank?

    parse_args

    # Generate migration
    generate_create_migration(@resource, @fields_to_migration) if options.migration?

    # Graphql Basic mutations
    generate_basic_mutations(@resource) if options.mutations?

    # Graphql Type
    generate_graphql_type(@resource) if options.graphql_type?

    # Graphql Connection
    generate_graphql_connection(resource) if options.connection?

    # Model
    generate_model(@resource) if options.model?

    # Service
    generate_service(@resource) if options.service?
    handle_many_to_many_fields(@resource) if options.propagation?

    # Propagation
    add_has_many_to_models(@resource) if options.propagation?
    add_has_many_fields_to_types(@resource) if options.propagation?

    system('bundle exec rails db:migrate') if options.migrate?
  end

  private

  def types_mapping(type)
    TYPES_MAPPING[type] || 'types.String'
  end

  def parse_args
    if Graphql::Rails::Api::Config.instance.id_type == :uuid
      @id_db_type = 'uuid'
      @id_type = 'types.String'
    else
      @id_db_type = 'integer'
      @id_type = 'types.ID'
    end

    @resource = file_name.singularize
    @has_many = []
    @many_to_many = []
    @mutations_directory = "#{graphql_resource_directory(@resource)}/mutations"
    @belongs_to_fields = {}

    @args = args.each_with_object({}) do |f, hash|
      next if f.split(':').count != 2

      case f.split(':').first
      when 'belongs_to' then
        hash["#{f.split(':').last.singularize}_id"] = @id_db_type
        @belongs_to_fields["#{f.split(':').last.singularize}_id"] = @id_db_type
      when 'has_many' then @has_many << f.split(':').last.pluralize
      when 'many_to_many' then @many_to_many << f.split(':').last.pluralize
      else
        hash[f.split(':').first] = f.split(':').last
      end
    end

    @fields_to_migration = @args.map do |f|
      "t.#{f.reverse.join(' :')}"
    end.join("\n      ")
  end

  def graphql_resource_directory(resource)
    "app/graphql/#{resource.pluralize}"
  end

  def generate_create_migration(resource, fields)
    system("bundle exec rails generate migration create_#{resource} --skip")
    migration_file = Dir.glob("db/migrate/*create_#{resource}.rb").last
    File.write(
      migration_file,
      <<~STRING
        class Create#{resource.camelize} < ActiveRecord::Migration[5.2]
          def change
            create_table :#{resource.pluralize}, #{'id: :uuid ' if Graphql::Rails::Api::Config.instance.id_type == :uuid}do |t|
              #{fields}
              t.timestamps
            end
          end
        end
      STRING
    )
  end

  def generate_basic_mutations(resource)
    system("mkdir -p #{@mutations_directory}")
    system("rails generate graphql_mutations #{resource}")

    # Graphql Input Type
    generate_graphql_input_type(resource) if options.graphql_input_type?
  end

  def generate_graphql_connection(resource)
    File.write(
      "#{graphql_resource_directory(resource)}/connection.rb",
      <<~STRING
        #{resource_class(resource)}::Connection = #{resource.pluralize.camelize}::Type.define_connection do
          name '#{resource.camelize}Connection'

          field :total_count, types.Int do
            resolve ->(obj, _, _) { obj.nodes.count }
          end
        end
      STRING
    )
  end

  def generate_graphql_input_type(resource)
    system("mkdir -p #{@mutations_directory}")
    File.write(
      "#{@mutations_directory}/input_type.rb",
      <<~STRING
        #{resource_class(resource)}::Mutations::InputType = GraphQL::InputObjectType.define do
          name '#{resource_class(resource).singularize}InputType'
          description 'Properties for updating a #{resource_class(resource).singularize}'

          #{map_types(input_type: true)}

        end
      STRING
    )
  end

  def generate_graphql_type(resource)
    File.write(
      "#{graphql_resource_directory(resource)}/type.rb",
      <<~STRING
        #{resource_class(resource)}::Type = GraphQL::ObjectType.define do
          name '#{resource_class(resource).singularize}'
          field :id, !#{@id_type}
          field :created_at, types.String
          field :updated_at, types.String
          #{map_types(input_type: false)}
        end
      STRING
    )
  end

  def generate_model(resource)
    generate_empty_model(resource)
  end

  def add_has_many_fields_to_type(field, resource)
    file_name = "app/graphql/#{field.pluralize}/type.rb"
    if File.read(file_name).include?("field :#{resource.singularize}_ids") ||
        File.read(file_name).include?("field :#{resource.pluralize}") ||
        File.read(file_name).include?("connection :#{resource.pluralize}_connection")
      return
    end
    write_at(
      file_name, 4,
      <<-STRING
  field :#{resource.singularize}_ids, types[#{@id_type}]
  field :#{resource.pluralize}, types[#{resource.pluralize.camelize}::Type]
  connection :#{resource.pluralize}_connection, #{resource.pluralize.camelize}::Connection
        STRING
    )

    input_type_file_name = "app/graphql/#{field.pluralize}/mutations/input_type.rb"
    if File.read(input_type_file_name).include?("argument :#{resource.singularize}_id") ||
        File.read(input_type_file_name).include?("argument :#{resource.singularize}")
      return
    end
    write_at(
      input_type_file_name, 4,
      <<-STRING
  argument :#{resource.singularize}_ids, types[#{@id_type}]
      STRING
    )

  end

  def add_belongs_to_field_to_type(field, resource)
    file_name = "app/graphql/#{resource.pluralize}/type.rb"
    if File.read(file_name).include?("field :#{field.singularize}_id") ||
        File.read(file_name).include?("field :#{field.singularize}")
      return
    end

    write_at(
      file_name, 4,
      <<-STRING
  field :#{field.singularize}_id, #{@id_type}
  field :#{field.singularize}, #{field.pluralize.camelize}::Type
      STRING
    )
    input_type_file_name = "app/graphql/#{resource.pluralize}/mutations/input_type.rb"
    if File.read(input_type_file_name).include?("argument :#{field.singularize}_id") ||
        File.read(input_type_file_name).include?("argument :#{field.singularize}")
      return
    end

    write_at(
      input_type_file_name, 4,
      <<-STRING
  argument :#{field.singularize}_id, #{@id_type}
      STRING
    )
  end

  def add_has_many_fields_to_types(resource)
    @has_many.each do |f|
      add_has_many_fields_to_type(resource, f)
      add_belongs_to_field_to_type(resource, f)
    end
    @belongs_to_fields.each do |f, _|
      add_has_many_fields_to_type(f.gsub('_id', ''), resource)
      add_belongs_to_field_to_type(f.gsub('_id', ''), resource)
    end
  end

  def generate_empty_model(resource)
    File.write(
      "app/models/#{resource}.rb",
      <<~STRING
        class #{resource.singularize.camelize} < ApplicationRecord

        end
      STRING
    )
  end

  def generate_service(resource)
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

  def handle_many_to_many_fields(resource)
    @many_to_many.each do |field|
      generate_create_migration(
        "#{resource}_#{field}",
        <<-STRING
t.#{@id_db_type} :#{resource.underscore.singularize}_id
      t.#{@id_db_type} :#{field.underscore.singularize}_id
        STRING
      )
      generate_empty_model("#{resource}_#{field.singularize}")
      add_to_model("#{resource}_#{field.singularize}", "belongs_to :#{resource.singularize}")
      add_to_model("#{resource}_#{field.singularize}", "belongs_to :#{field.singularize}")
      add_to_model(resource, "has_many :#{field.pluralize}, through: :#{resource}_#{field.pluralize}")
      add_to_model(resource, "has_many :#{resource}_#{field.pluralize}")
      add_to_model(field, "has_many :#{resource.pluralize}, through: :#{resource}_#{field.pluralize}")
      add_to_model(field, "has_many :#{resource}_#{field.pluralize}")
      add_has_many_fields_to_type(resource, field)
      add_has_many_fields_to_type(field, resource)
    end
  end

  def add_has_many_to_models(resource)
    @has_many.each do |field|
      generate_has_many_migration(resource, has_many: field)
      add_to_model(resource, "has_many :#{field.pluralize}")
      add_to_model(field, "belongs_to :#{resource.singularize}")
    end
    @belongs_to_fields.each do |k, _|
      field = k.gsub('_id', '')
      add_to_model(field, "has_many :#{resource.pluralize}")
      add_to_model(resource, "belongs_to :#{field.singularize}")
    end
  end

  def map_types(input_type: false)
    result = args&.map do |k, v|
      field_name = k
      field_type = types_mapping(v)
      res = "#{input_type ? 'argument' : 'field'} :#{field_name}, #{field_type}"
      if !input_type && field_name.ends_with?('_id') && @belongs_to_fields.key?(field_name)
        res += "\n  field :#{field_name.gsub('_id', '')}, " \
          "#{field_name.gsub('_id', '').pluralize.camelize}::Type"
      end
      res
    end&.join("\n  ")
    input_type ? result.gsub("field :id, #{@id_type}\n", '') : result
  end

  # Helpers methods

  def resource_class(resource)
    resource.pluralize.camelize
  end

  def add_to_model(model, line)
    file_name = "app/models/#{model.underscore.singularize}.rb"
    return if !File.exist?(file_name) || File.read(file_name).include?(line)

    line_count = `wc -l "#{file_name}"`.strip.split(' ')[0].to_i

    line_nb = 0
    File.open(file_name).each do |l|
      line_nb += 1
      break if l.include?('ApplicationRecord')
    end
    raise 'Your model must inherit from ApplicationRecord to make it work' if line_nb >= line_count

    write_at(file_name, line_nb + 2, "  #{line}\n")
  end

  def generate_has_many_migration(resource, has_many:)
    return if has_many.singularize.camelize.constantize.new.respond_to?("#{resource.singularize}_id")

    system("bundle exec rails generate migration add_#{resource.singularize}_id_to_#{has_many}")
    migration_file = Dir.glob("db/migrate/*add_#{resource.singularize}_id_to_#{has_many}.rb").last
    File.write(
      migration_file,
      <<~STRING
        class Add#{resource.singularize.camelize}IdTo#{has_many.camelize} < ActiveRecord::Migration[5.2]
          def change
            add_column :#{has_many.pluralize}, :#{resource.singularize}_id, :#{@id_db_type}
          end
        end
      STRING
    )
  end

  def generate_belongs_to_migration(resource, belongs_to:)
    generate_has_many_migration(belongs_to, has_many: resource)
  end

  def write_at(file_name, line, data)
    open(file_name, 'r+') do |f|
      while (line -= 1).positive?
        f.readline
      end
      pos = f.pos
      rest = f.read
      f.seek(pos)
      f.write(data)
      f.write(rest)
    end
  end

end
