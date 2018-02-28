class GraphqlResourceGenerator < Rails::Generators::NamedBase

  %i[migration model mutations service graphql_input_type graphql_type propagation].each do |opt|
    class_option(opt, type: :boolean, default: true)
  end

  TYPES_MAPPING = {
    'types.Uuid' => '!types.String',
    'types.Text' => 'types.String',
    'types.Datetime' => 'types.String',
    'types.Integer' => 'types.Int',
    'types.Json' => 'types.String',
    'types.Id' => '!types.ID',
    'types.String' => 'types.String',
    'types.Float' => 'types.Float'
  }.freeze

  def create_graphql_files
    @graphql_resource_directory = "app/graphql/#{resource.pluralize}"
    @mutations_directory = "#{@graphql_resource_directory}/mutations"
    @args = args
    @id_type = Graphql::Rails::Api::Config.instance.id_type == :uuid ? '!types.String' : '!types.ID'
    @id_fields = @args&.map { |f| f.split(':').first }.to_a.select { |f| f.ends_with?('_id') }

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
  end

  private

  def generate_migration
    fields_to_migration = args&.map do |f|
      "t.#{f.split(':').reverse.join(' :')}"
    end.join("\n      ")
    system("bundle exec rails generate migration create_#{resource} --skip")
    migration_file = Dir.glob("db/migrate/*create_#{resource}*").last
    File.write(
      migration_file,
      <<~STRING
        class Create#{resource.camelize} < ActiveRecord::Migration[5.1]
          def change
            create_table :#{resource.pluralize}, #{'id: :uuid ' if Graphql::Rails::Api::Config.instance.id_type == :uuid}do |t|
              #{fields_to_migration}
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

  def add_has_many_fields_to_types
    @id_fields.each do |f|
      write_at(
        "app/graphql/#{f.gsub('_id', '').pluralize}/type.rb", 5,
        <<-STRING
  field :#{resource.singularize}_ids, !types[#{@id_type}]
  field :#{resource.pluralize}, !types[!#{resource.pluralize.camelize}::Type] do
    resolve ->(obj, _, ctx) { obj.#{resource.pluralize}.visible_for(user: ctx[:current_user]) }
  end
        STRING
      )
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

  def add_has_many_to_models
    @id_fields.each do |f|
      write_at(
        "app/models/#{f.gsub('_id', '').singularize}.rb", 3, "  has_many :#{resource.pluralize}\n"
      )
    end
  end

  def generate_belongs_to
    @id_fields.map do |f|
      "belongs_to :#{f.gsub('_id', '')}"
    end.join("\n  ") + "\n"
  end

  def map_types(input_type: false)
    result = args&.map do |f|
      field_name = f.split(':').first
      field_type = TYPES_MAPPING[f.split(':').last.capitalize.prepend('types.')]
      res = "#{input_type ? 'argument' : 'field'} :#{field_name}, #{field_type}"
      if !input_type && field_name.ends_with?('_id')
        res += "\n  field :#{field_name.gsub('_id', '')}, " \
          "!#{field_name.pluralize.gsub('_id', '').camelize}::Type"
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
