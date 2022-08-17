require "deep_pluck"
require "rkelly"

module Graphql
  class HydrateQuery
    def initialize(model, context, order_by: nil, filter: nil, check_visibility: true, id: nil, user: nil, page: nil, per_page: nil)
      @context = context
      @filter = filter
      @order_by = order_by
      @model = model
      @check_visibility = check_visibility

      if id.present? && !valid_id?(id)
        raise GraphQL::ExecutionError, "Invalid id: #{id}"
      end

      @id = id
      @user = user
      @page = page&.to_i || 1
      @per_page = per_page&.to_i || 1000
      @per_page = 1000 if @per_page > 1000
    end

    def run
      if @id
        @model = @model.where(id: @id)
        deep_pluck_to_structs(@context&.irep_node).first
      else
        @model = @model.limit(@per_page)
        @model = @model.offset(@per_page * (@page - 1))

        transform_filter if @filter.present?
        transform_order if @order_by.present?

        deep_pluck_to_structs(@context&.irep_node)
      end
    end

    def paginated_run
      transform_filter if @filter.present?
      transform_order if @order_by.present?

      @total = @model.length
      @model = @model.limit(@per_page)
      @model = @model.offset(@per_page * (@page - 1))

      OpenStruct.new(
        data: deep_pluck_to_structs(@context&.irep_node&.typed_children&.values&.first.try(:[], "data")),
        total_count: @total,
        per_page: @per_page,
        page: @page,
      )
    end

    private

    def transform_order
      return if @order_by.blank?

      sign = @order_by.split(" ").last.downcase == "desc" ? "desc" : "asc"
      column = @order_by.split(" ").first.strip

      if column.include?(".")
        associated_model = column.split(".").first
        accessor = column.split(".").last
        assoc = get_assoc!(@model, associated_model)
        field_type = get_field_type!(assoc.klass, accessor)
        @model = @model.left_joins(associated_model.to_sym)
        ordered_field = "#{associated_model.pluralize}.#{accessor}"
      else
        field_type = get_field_type!(@model, column)
        ordered_field = "#{model_name.pluralize}.#{column}"
      end

      if %i[string text].include?(field_type)
        @model = @model.order(Arel.sql("upper(#{ordered_field}) #{sign}"))
      else
        @model = @model.order(Arel.sql("#{ordered_field} #{sign}"))
      end
    end

    def transform_filter
      return if @filter.blank?

      ast = RKelly::Parser.new.parse(@filter)
      exprs = ast.value
      if exprs.count != 1
        raise GraphQL::ExecutionError, "Invalid filter: #{@filter}, only one expression allowed"
      end

      @model = handle_node(exprs.first.value, @model)

      if @need_distinct_results
        @model = @model.distinct
      end

    rescue RKelly::SyntaxError => e
      raise GraphQL::ExecutionError, "Invalid filter: #{e.message}"
    end

    def handle_node(node, model)
      if node.class == RKelly::Nodes::ParentheticalNode
        handle_ParentheticalNode(node, model)
      elsif node.class == RKelly::Nodes::LogicalAndNode
        handle_LogicalAndNode(node, model)
      elsif node.class == RKelly::Nodes::LogicalOrNode
        handle_LogicalOrNode(node, model)
      elsif node.class == RKelly::Nodes::NotEqualNode
        handle_NotEqualNode(node, model)
      elsif node.class == RKelly::Nodes::EqualNode
        handle_EqualNode(node, model)
      elsif node.class == RKelly::Nodes::StrictEqualNode
        handle_StrictEqualNode(node, model)
      elsif node.class == RKelly::Nodes::NotStrictEqualNode
        handle_NotStrictEqualNode(node, model)
      elsif node.class == RKelly::Nodes::GreaterOrEqualNode
        handle_GreaterOrEqualNode(node, model)
      elsif node.class == RKelly::Nodes::LessOrEqualNode
        handle_LessOrEqualNode(node, model)
      elsif node.class == RKelly::Nodes::LessNode
        handle_LessNode(node, model)
      elsif node.class == RKelly::Nodes::GreaterNode
        handle_GreaterNode(node, model)
      else
        raise GraphQL::ExecutionError, "Invalid filter: #{node.class} unknown operator"
      end
    end

    def handle_ParentheticalNode(node, model)
      handle_node(node.value, model)
    end

    def handle_LogicalAndNode(node, model)
      handle_node(node.left, model).and(handle_node(node.value, model))
    end

    def handle_LogicalOrNode(node, model)
      handle_node(node.left, model).or(handle_node(node.value, model))
    end

    def handle_dot_accessor_node(node, model)
      associated_model = node.left.value.value
      accessor = node.left.accessor
      assoc = get_assoc!(model, associated_model)
      field_type = get_field_type!(assoc.klass, accessor)

      if assoc.association_class == ActiveRecord::Associations::HasManyAssociation
        @need_distinct_results = true
      end

      model = model.left_joins(associated_model.to_sym)
      # field = "#{associated_model.pluralize}.#{accessor}"
      value = value_from_node(node.value, field_type, accessor.to_sym, model)
      [assoc.klass.arel_table[accessor], model, field_type, value]
    end

    def handle_resolve_node(node, model)
      field = node.left.value
      field_type = get_field_type!(model, field)
      value = value_from_node(node.value, field_type, field.to_sym, model)
      [model.klass.arel_table[field], model, field_type, value]
    end

    def handle_operator_node(node, model)
      if node.left.class == RKelly::Nodes::DotAccessorNode
        handle_dot_accessor_node(node, model)
      elsif node.left.class == RKelly::Nodes::ResolveNode
        handle_resolve_node(node, model)
      else
        raise GraphQL::ExecutionError, "Invalid left value: #{node.left.class}"
      end
    end

    def value_from_node(node, sym_type, sym, model)
      if node.class == RKelly::Nodes::StringNode
        val = node.value.gsub(/^'|'$|^"|"$/, "")
        if sym_type == :datetime
          DateTime.parse(val)
        elsif sym_type == :date
          Date.parse(val)
        elsif sym_type == :integer
          # Enums are handled here : We are about to compare a string with an integer column
          # If the symbol and the value correspond to an existing enum into the model
          if model.klass.defined_enums[sym.to_s]&.keys&.include?(val)
            # return the corresponding enum value
            model.klass.defined_enums[sym.to_s][val]
          else
            raise GraphQL::ExecutionError, "Invalid value: #{val}, compare a string with an integer column #{sym}"
          end
        else
          val
        end
      elsif node.class == RKelly::Nodes::NumberNode
        node.value
      elsif node.class == RKelly::Nodes::TrueNode
        true
      elsif node.class == RKelly::Nodes::FalseNode
        false
      elsif node.class == RKelly::Nodes::NullNode
        nil
      else
        raise GraphQL::ExecutionError, "Invalid filter: #{node} unknown rvalue node"
      end
    end

    def sanitize_sql_like(value)
      ActiveRecord::Base::sanitize_sql_like(value)
    end

    def handle_NotEqualNode(node, model)
      arel_field, model, type, value = handle_operator_node(node, model)

      if value.nil?
        model.where.not(arel_field.eq(nil))
      elsif type == :text || type == :string
        model.where.not(arel_field.lower.matches(sanitize_sql_like(value.downcase)))
      else
        model.where.not(arel_field.eq(value))
      end
    end

    def handle_NotStrictEqualNode(node, model)
      arel_field, model, type, value = handle_operator_node(node, model)

      if value.nil?
        model.where.not(arel_field.eq(nil))
      elsif type == :text || type == :string
        model.where.not(arel_field.matches(sanitize_sql_like(value), false, true))
      else
        model.where.not(arel_field.eq(value))
      end
    end

    def handle_EqualNode(node, model)
      arel_field, model, type, value = handle_operator_node(node, model)

      if value.nil?
        model.where(arel_field.eq(nil))
      elsif type == :text || type == :string
        model.where(arel_field.lower.matches(sanitize_sql_like(value.downcase)))
      else
        model.where(arel_field.eq(value))
      end
    end

    def handle_StrictEqualNode(node, model)
      arel_field, model, type, value = handle_operator_node(node, model)

      if value.nil?
        model.where(arel_field.eq(nil))
      elsif type == :text || type == :string
        model.where(arel_field.matches(sanitize_sql_like(value), false, true))
      else
        model.where(arel_field.eq(value))
      end
    end

    def handle_GreaterOrEqualNode(node, model)
      arel_field, model, type, value = handle_operator_node(node, model)
      model.where(arel_field.gteq(value))
    end

    def handle_LessOrEqualNode(node, model)
      arel_field, model, type, value = handle_operator_node(node, model)
      model.where(arel_field.lteq(value))
    end

    def handle_LessNode(node, model)
      arel_field, model, type, value = handle_operator_node(node, model)
      model.where(arel_field.lt(value))
    end

    def handle_GreaterNode(node, model)
      arel_field, model, type, value = handle_operator_node(node, model)
      model.where(arel_field.gt(value))
    end

    def valid_id?(id)
      valid_uuid?(id) || id.is_a?(Integer)
    end

    def valid_uuid?(id)
      id.to_s.match(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/)
    end

    def get_assoc!(model, assoc_name)
      assoc = model.reflect_on_association(assoc_name)
      unless assoc.present?
        raise GraphQL::ExecutionError, "Invalid filter: #{assoc_name} is not an association of #{model}"
      end
      assoc
    end

    def get_field_type!(model, field_name)
      field = model.column_for_attribute(field_name.to_sym)
      unless field.present?
        raise GraphQL::ExecutionError, "Invalid filter: #{field_name} is not a field of #{model}"
      end
      field.type
    end

    def deep_pluck_to_structs(irep_node)
      plucked_attr_to_structs(
        DeepPluck::Model.new(@model.visible_for(user: @user), user: @user).add(
          ((hash_to_array_of_hashes(parse_fields(irep_node), @model) || []) + [@to_select_to_add]).compact
        ).load_all,
        model_name.singularize.camelize.constantize
      )&.compact
    end

    def plucked_attr_to_structs(arr, parent_model)
      arr.map { |e| hash_to_struct(e, parent_model) }
    end

    def hash_to_struct(hash, parent_model)
      hash.each_with_object(OpenStruct.new) do |(k, v), struct|
        m = evaluate_model(parent_model, k)

        next struct[k.to_sym] = plucked_attr_to_structs(v, m) if v.is_a?(Array) && m

        next struct[k.to_sym] = hash_to_struct(v, m) if v.is_a?(Hash) && m

        struct[k.to_sym] = v
      end
    end

    def hash_to_array_of_hashes(hash, parent_class)
      return if parent_class.nil? || hash.nil?

      hash["id"] = nil if hash["id"].blank?
      fetch_ids_from_relation(hash)

      hash.each_with_object([]) do |(k, v), arr|
        next arr << k if parent_class.new.attributes.key?(k)
        next arr << v if parent_class.new.attributes.key?(v)

        klass = evaluate_model(parent_class, k)
        arr << { k.to_sym => hash_to_array_of_hashes(v, klass) } if klass.present? && v.present?
      end
    end

    def fetch_ids_from_relation(hash)
      hash.select { |k, _| k.ends_with?("_ids") }.each do |(k, _)|
        collection_name = k.gsub("_ids", "").pluralize
        if hash[collection_name].blank?
          hash[collection_name] = { "id" => nil }
        else
          hash[collection_name]["id"] = nil
        end
      end
    end

    def activerecord_model?(name)
      class_name = name.to_s.singularize.camelize
      begin
        class_name.constantize.ancestors.include?(ApplicationRecord)
      rescue NameError
        false
      end
    end

    def evaluate_model(parent, child)
      return unless parent.reflect_on_association(child)

      child_class_name = parent.reflect_on_association(child).class_name
      parent_class_name = parent.to_s.singularize.camelize

      return child_class_name.constantize if activerecord_model?(child_class_name)

      return unless activerecord_model?(parent_class_name)

      parent_class_name.constantize.reflections[child.to_s.underscore]&.klass
    end

    def parse_fields(irep_node)
      fields = irep_node&.scoped_children&.values&.first
      fields = fields["edges"].scoped_children.values.first["node"]&.scoped_children&.values&.first if fields&.key?("edges")
      return if fields.blank?

      fields.each_with_object({}) do |(k, v), h|
        h[k] = v.scoped_children == {} ? v.definition.name : parse_fields(v)
      end
    end

    def model_name
      @model.class.to_s.split("::").first.underscore.pluralize
    end
  end
end
