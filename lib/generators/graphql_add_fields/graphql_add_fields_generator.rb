class GraphqlAddFieldsGenerator < Rails::Generators::NamedBase

  %i[
    migration model mutations service graphql_input_type
    graphql_type propagation connection migrate
  ].each do |opt|
    class_option(opt, type: :boolean, default: true)
  end

  TYPES_MAPPING = {
    'id' => 'String',
    'uuid' => 'String',
    'boolean' => 'Boolean',
    'float' => 'Float',
    'decimal' => 'Float',
    'integer' => 'Integer',
    'bigint' => 'Integer'
  }.freeze

  def create_graphql_files
    return if args.blank?

    parse_args

    # Generate migration
    generate_migration(@resource, @fields_to_migration) if options.migration?

    complete_graphql_input_type if options.graphql_input_type?

    # # Graphql Type
    complete_graphql_type(@resource) if options.graphql_type?

    # # Propagation
    handle_many_to_many_fields(@resource) if options.propagation?
    add_has_many_to_models(@resource) if options.propagation?
    add_has_many_fields_to_types(@resource) if options.propagation?

    # system('bundle exec rails db:migrate') if options.migrate?
  end

  private

  def types_mapping(type)
    TYPES_MAPPING[type] || 'String'
  end

  def complete_graphql_input_type
    return if map_types(input_type: true).blank?

    write_at("#{@mutations_directory}/input_type.rb", 7, "      #{map_types(input_type: true)}\n")
  end

  def complete_graphql_type(resource)
    return if map_types(input_type: false).blank?

    write_at("#{graphql_resource_directory(resource)}/type.rb", 6, "    #{map_types(input_type: false)}\n")
  end

  def parse_args
    @id_db_type = 'uuid'
    @id_type = 'String'

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
      "add_column :#{@resource.pluralize}, :#{f.join(', :')}"
    end.join("\n    ")
    @named_fields = @args.keys.join('_')
  end

  def generate_migration(resource, fields)
    return if @named_fields.blank?

    system("bundle exec rails generate migration add_#{@named_fields}_to_#{resource} --skip")
    File.write(
      Dir.glob("db/migrate/*add_#{@named_fields}_to_#{resource}.rb").last,
      <<~STRING
        class Add#{@named_fields.camelize}To#{resource.camelize} < ActiveRecord::Migration[5.2]
          def change
            #{fields}
          end
        end
      STRING
    )
  end

  def graphql_resource_directory(resource)
    "app/graphql/#{resource.pluralize}"
  end

  def add_has_many_fields_to_type(field, resource)
    file_name = "app/graphql/#{field.pluralize}/type.rb"
    if File.read(file_name).include?("field :#{resource.singularize}_ids") ||
        File.read(file_name).include?("field :#{resource.pluralize}")
      return
    end

    write_at(
      file_name, 6,
      "    field :#{resource.pluralize}, [#{resource.pluralize.camelize}::Type], null: true\n"
    )

    input_type_file_name = "app/graphql/#{field.pluralize}/mutations/input_type.rb"
    if File.read(input_type_file_name).include?("argument :#{resource.singularize}_id") ||
        File.read(input_type_file_name).include?("argument :#{resource.singularize}")
      return
    end

    write_at(
      input_type_file_name, 7,
      "      argument :#{resource.singularize}_ids, [#{@id_type}], required: false\n"
    )
  end

  def add_belongs_to_field_to_type(field, resource)
    file_name = "app/graphql/#{resource.pluralize}/type.rb"
    if File.read(file_name).include?("field :#{field.singularize}_id") ||
        File.read(file_name).include?("field :#{field.singularize}")
      return
    end

    write_at(
      file_name, 6,
      "    field :#{field.singularize}_id, #{@id_type}, null: false\n    field :#{field.singularize}, #{field.pluralize.camelize}::Type, null: false\n"
    )
    input_type_file_name = "app/graphql/#{resource.pluralize}/mutations/input_type.rb"
    if File.read(input_type_file_name).include?("argument :#{field.singularize}_id") ||
        File.read(input_type_file_name).include?("argument :#{field.singularize}")
      return
    end

    write_at(
      input_type_file_name, 7,
      "      argument :#{field.singularize}_id, #{@id_type}, required: false\n"
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
      res = "#{input_type ? 'argument' : 'field'} :#{field_name}, #{field_type}, #{input_type ? "required: false" : "null: true"}"
      if !input_type && field_name.ends_with?('_id') && @belongs_to_fields.key?(field_name)
        res += "\n    field :#{field_name.gsub('_id', '')}, " \
          "#{field_name.gsub('_id', '').pluralize.camelize}::Type"
      end
      res
    end&.join("\n    " + ("  " if input_type).to_s)
    input_type ? result.gsub("field :id, #{@id_type}, null: false\n", '') : result
  end

  # Helpers methods

  def resource_class(resource)
    resource.pluralize.camelize
  end

  def add_to_model(model, line)
    file_name = "app/models/#{model.underscore.singularize}.rb"
    return if !File.exist?(file_name) || File.read(file_name).include?(line)

    file = open(file_name)
    line_count = file.readlines.size
    line_nb = 0
    IO.readlines(file).each do |l|
      line_nb += 1
      break if l.include?('ApplicationRecord')
    end
    raise 'Your model must inherit from ApplicationRecord to make it work' if line_nb >= line_count

    write_at(file_name, line_nb + 1, "  #{line}\n")
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

  def generate_create_migration(resource, fields)
    system("bundle exec rails generate migration create_#{resource} --skip")
    migration_file = Dir.glob("db/migrate/*create_#{resource}.rb").last
    File.write(
      migration_file,
      <<~STRING
        class Create#{resource.camelize} < ActiveRecord::Migration[5.2]
          def change
            create_table :#{resource.pluralize}, id: :uuid do |t|
              #{fields}
              t.timestamps
            end
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
