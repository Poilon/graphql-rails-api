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
      # filter on an association
      associated_model = node.left.value.value
      # verify association exists
      if !model.reflect_on_association(associated_model)
        raise GraphQL::ExecutionError, "Invalid filter: #{associated_model} is not an association"
      end
      assoc = model.reflect_on_association(associated_model)
      associated_model_class = assoc.klass
      @need_distinct_results = true if assoc.association_class == ActiveRecord::Associations::HasManyAssociation
      accessor = node.left.accessor
      field_type = associated_model_class.column_for_attribute(accessor).type
      if !associated_model_class.column_names.include?(accessor)
        # verify that the attribute is a valid attribute of associated model
        raise GraphQL::ExecutionError, "Invalid filter: #{accessor} is not a valid field of #{associated_model}"
      end
      model = model.left_joins(associated_model.to_sym)
      field = "#{associated_model.pluralize}.#{accessor}"
      value = value_from_node(node.value, field_type, accessor.to_sym, model)
      [model, field, field_type, value]
    end

    def handle_resolve_node(node, model)
      field = node.left.value
      if !model.column_names.include?(field)
        # verify that the attribute is a valid attribute of @model
        raise GraphQL::ExecutionError, "Invalid left value: #{field}"
      end
      field_type = model.column_for_attribute(field.to_sym).type
      value = value_from_node(node.value, field_type, field.to_sym, model)
      [model, "#{@model.klass.to_s.downcase.pluralize}.#{field}", field_type, value]
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
          # We are about to compare a string with an integer column
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

    def handle_NotEqualNode(node, model)
      model, field, type, value = handle_operator_node(node, model)

      if value.nil?
        model.where("#{field} IS NOT NULL")
      elsif type == :text || type == :string
        model.where.not("#{field} ILIKE ?", value)
      else
        model.where.not("#{field} = ?", value)
      end
    end

    def handle_NotStrictEqualNode(node, model)
      model, field, type, value = handle_operator_node(node, model)

      if value.nil?
        model.where("#{field} IS NOT NULL")
      elsif type == :text || type == :string
        model.where.not("#{field} LIKE ?", value)
      else
        model.where.not("#{field} = ?", value)
      end
    end

    def handle_EqualNode(node, model)
      model, field, type, value = handle_operator_node(node, model)

      if value.nil?
        model.where("#{field} IS NULL")
      elsif type == :text || type == :string
        model.where("#{field} ILIKE ?", value)
      else
        model.where("#{field} = ?", value)
      end
    end

    def handle_StrictEqualNode(node, model)
      model, field, type, value = handle_operator_node(node, model)

      if value.nil?
        model.where("#{field} IS NULL")
      elsif type == :text || type == :string
        model.where("#{field} LIKE ?", value)
      else
        model.where("#{field} = ?", value)
      end
    end

    def handle_GreaterOrEqualNode(node, model)
      model, field, type, value = handle_operator_node(node, model)
      model.where("#{field} >= ?", value)
    end

    def handle_LessOrEqualNode(node, model)
      model, field, type, value = handle_operator_node(node, model)
      model.where("#{field} <= ?", value)
    end

    def handle_LessNode(node, model)
      model, field, type, value = handle_operator_node(node, model)
      model.where("#{field} < ?", value)
    end

    def handle_GreaterNode(node, model)
      model, field, type, value = handle_operator_node(node, model)
      model.where("#{field} > ?", value)
    end

    def valid_id?(id)
      valid_uuid?(id) || id.is_a?(Integer)
    end

    def valid_uuid?(id)
      id.to_s.match(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/)
    end

    def transform_order
      return if @order_by.blank?

      sign = @order_by.split(" ").last.downcase == "desc" ? "desc" : "asc"
      column = @order_by.split(" ").first.strip

      if column.include?(".")
        associated_model = column.split(".").first
        column = column.split(".").last
        associated_model_class = @model.reflect_on_association(associated_model)&.klass

        unless associated_model_class.present?
          raise GraphQL::ExecutionError, "Invalid order: #{associated_model} is not an association"
        end

        unless associated_model_class.column_names.include?(column)
          raise GraphQL::ExecutionError, "Invalid order: #{column} is not a valid field of #{associated_model}"
        end

        @model = @model.left_joins(associated_model.to_sym)
        type = associated_model_class.columns_hash[column].type
        if %i[string text].include?(type)
          @model = @model.order(Arel.sql("upper(#{associated_model.pluralize}.#{column}) #{sign}"))
        else
          @model = @model.order(Arel.sql("#{associated_model.pluralize}.#{column}) #{sign}"))
        end
      else
        unless @model.column_names.include?(column)
          raise GraphQL::ExecutionError, "Invalid order: #{column} is not a valid field of #{associated_model}"
        end
        type = @model.columns_hash[column].type
        if %i[string text].include?(type)
          @model = @model.order("upper(#{model_name}.#{column}) #{sign}")
        else
          @model = @model.order("#{model_name}.#{column} #{sign}")
        end
      end
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
