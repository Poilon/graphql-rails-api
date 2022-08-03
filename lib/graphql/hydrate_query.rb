require 'deep_pluck'
require 'rkelly'

module Graphql
  class HydrateQuery

    def initialize(model, context, order_by: nil, filter: nil, check_visibility: true, id: nil, user: nil, page: nil, per_page: nil)
      ::Rails.logger.error("Context #{context}")
      @context = context
      @filter = filter
      @order_by = order_by
      @model = model
      @check_visibility = check_visibility

      if @id.present? && !valid_id?(@id)
        raise GraphQL::ExecutionError, "Invalid id: #{@id}"
      end

      @id = id
      @user = user
      @page = page.present? ? page.to_i : 1
      #@page = page || 1
      #@per_page = per_page.to_i || 1000
      # params[:per_page] && params[:per_page] > 1000 ? 1000 : params[:per_page]
      @per_page = per_page.present? ? per_page.to_i :  1000
    end

    def run
      if @id
        @model = @model.where(id: @id)
        deep_pluck_to_structs(@context&.irep_node).first
      else
        @model = @model.limit(@per_page)
        @model = @model.offset(@per_page * (@page - 1))

        # filter_and_order
        transform_filter if @filter
        transform_order if @order_by

        deep_pluck_to_structs(@context&.irep_node)
      end
    end

    def paginated_run
      # filter_and_order
      transform_filter if @filter
      transform_order if @order_by

      @total = @model.length
      @model = @model.limit(@per_page)
      @model = @model.offset(@per_page * (@page - 1))

      ::Rails.logger.info(@model.to_sql)
      OpenStruct.new(
        data: deep_pluck_to_structs(@context&.irep_node&.typed_children&.values&.first.try(:[], 'data')),
        total_count: @total,
        per_page: @per_page,
        page: @page
      )
    end

    private

    def valid_id?(id)
      valid_uuid?(id) || id.is_a?(Integer)
    end

    def valid_uuid?(id)
      id.to_s.match(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/)
    end

    def allowed_node?(node)
      [
        # Source and expression node
        RKelly::Nodes::SourceElementsNode,
        RKelly::Nodes::ExpressionStatementNode,
        # Parenthesis
        RKelly::Nodes::ParentheticalNode,
        # Logical operators
        RKelly::Nodes::LogicalAndNode,
        RKelly::Nodes::LogicalOrNode,
        # Comparaison operators
        RKelly::Nodes::NotEqualNode,
        RKelly::Nodes::EqualNode,
        RKelly::Nodes::StrictEqualNode,
        RKelly::Nodes::GreaterOrEqualNode,
        RKelly::Nodes::LessOrEqualNode,
        RKelly::Nodes::LessNode,
        RKelly::Nodes::GreaterNode,
        # left value
        RKelly::Nodes::ResolveNode,
        RKelly::Nodes::DotAccessorNode,
        # Leaf nodes : right value
        RKelly::Nodes::StringNode,
        RKelly::Nodes::NumberNode,
        RKelly::Nodes::TrueNode,
        RKelly::Nodes::FalseNode,
        RKelly::Nodes::NullNode,
      ].include?(node.class)
    end

    def comparaison_operator?(node)
      [
        RKelly::Nodes::NotEqualNode,
        RKelly::Nodes::EqualNode,
        RKelly::Nodes::StrictEqualNode,
        RKelly::Nodes::GreaterOrEqualNode,
        RKelly::Nodes::LessOrEqualNode,
        RKelly::Nodes::LessNode,
        RKelly::Nodes::GreaterNode,
      ].include?(node.class)
    end

    def handle_left_value(lvalue, accessor)
      # This is a comparaison left value node
      if accessor.present?
        # The filter is performed on an associated model attribute (accessor)
        associated_model = lvalue.value.to_sym
        # transform associated model name to class name
        associated_model_class = lvalue.value.camelize.constantize
        unless @model.klass.reflect_on_association(associated_model) &&
          associated_model_class.column_names.include?(accessor)
          raise GraphQL::ExecutionError, "Invalid left value: #{lvalue}"
        end

        # Handle 1 level association performing left join
        @model = @model.left_joins(associated_model)
      elsif !@model.column_names.include?(lvalue)
        # verify that the attribute is a valid attribute of @model
        raise GraphQL::ExecutionError, "Invalid left value: #{lvalue}"
      end
    end

    def sanitize(rvalue)
      # This is a comparaison right value node
      # Escape the string to avoid sqli
      # node.value = ActiveRecord::Base.connection.quote(node.value)
      rvalue
    end

    def is_enum_field?(field)
      if field.include?('.')
        # The filter is performed on an associated model attribute
        tmp = field.split('.')
        associated_model = tmp.first.to_sym
        attribute = tmp.last.to_sym
        # transform associated model name to class name
        associated_model_class = associated_model.to_s.camelize.constantize
        return associated_model_class.defined_enums.include?(attribute)
      end
      @model.klass.defined_enums.include?(field)
    end

    def enum_str_to_i(lvalue, rvalue)

      if lvalue.include?('.')
        # The filter is performed on an associated model attribute
        tmp = lvalue.split('.')
        associated_model = tmp.first.to_sym
        attribute = tmp.last.to_sym
        # transform associated model name to class name
        associated_model_class = associated_model.to_s.camelize.constantize
        ret = associated_model_class.defined_enums.values.reduce(:merge)[rvalue.delete("'")]
      else
        ret = @model.klass.defined_enums.values.reduce(:merge)[rvalue.delete("'")]
      end

      unless ret.present?
        raise GraphQL::ExecutionError, "Invalid right value #{rvalue} on enum #{lvalue}"
      end
      ret
    end

    def transform_filter
      #remove_from_filter=""
      begin
        ast = RKelly::Parser.new.parse(@filter)
      rescue RKelly::SyntaxError => e
        raise GraphQL::ExecutionError, "Invalid filter: #{e.message}"
      end

      # Iterate on the AST nodes to verify filter syntax
      ast.each do |node|
        unless allowed_node?(node)
          raise GraphQL::ExecutionError, "Invalid node type in filter: #{node.class}"
        end

        if node.class == RKelly::Nodes::DotAccessorNode
          #binding.pry
        end
        # TODO.
        # if node if an operator node find the left and right value
        # transform enum string to integer
        # transform date string to date

        #if comparaison_operator?(node)
        #  left_node = node.left
        #  #remove_from_filter = "#{node.left.value}."
        #  #if node.left.accessor.present?
        #  #  accessor = node.left.accessor
        #  #end
#
        #  right_node = node.value
#
        #  handle_left_value(left_node.value, nil)
        #  right_node.value = sanitize(right_node.value) if right_node.class == RKelly::Nodes::StringNode
#
        #  # handle enum transformation
        #  if is_enum_field?(left_node.value)
        #    right_node.value = enum_str_to_i(left_node.value, right_node.value)
        #  end
        #  # verify the corresponding left value is an enum and that the right value is a valid enum value
        #  # and check type compatibility
        #end
#
        #if node.class == RKelly::Nodes::ResolveNode
        #elsif node.class == RKelly::Nodes::StringNode


        #if node.value.is_a?(String)
        ::Rails.logger.info("Node: #{node.class} , #{node.value}")
        # end
      end

      parsed_filter = ast.to_ecma.delete(';')
      return '' unless parsed_filter.present?

      symbols = {
        '|': 'ilike',
        '||': 'OR',
        '&&': 'AND',
        '===': '=',
        '==': '=',
        '!= null': 'IS NOT NULL',
        '= null': 'IS NULL'
      }
      symbols.each { |k, v| parsed_filter.gsub!(" #{k} ", " #{v} ") }
      # parsed_filter.delete!(remove_from_filter)
      @model = @model.where(parsed_filter)
      #delimiters = ['AND', 'OR']
      #operators = [' ilike ', ' like ', '=', 'IS NOT NULL', 'IS NULL', '<', '<=', '>', '>=']
      #@model.klass.defined_enums.values.reduce(:merge)&.each { |k, v| parsed_filter.gsub!(" '#{k}'", " #{v}") }
      # parsed_filter.delete!(';')

      ::Rails.logger.error("Filter: #{parsed_filter}")
      ::Rails.logger.error("model: #{@model.to_sql}")

      # TODO handle  '!= null' '= null' in right value ...
      # TODO handle  'NOT' operator in left value ...
      #comparaison_operators = {
      #  '==':  'ilike',
      #  '===': 'like',
      #  '!=':  '!=',
      #  '<':   '<',
      #  '>':   '>',
      #  '<=':  '<=',
      #  '>=':  '>='
      #}
      #
      #logical_operators = {
      #  '&&': 'AND',
      #  '||': 'OR'
      #}

      # filters = parsed_filter.split(Regexp.union(delimiters))
      # filters.each do |f|
      #   values = f.split(Regexp.union(operators))
      #   lvalue = values.first&.strip
      #   rvalue = values.second&.strip
      #   return if invalid_format(lvalue) || invalid_format(rvalue)
#
      #   if lvalue&.include?('.')
      #     lvalue_model = lvalue.split('.').first.to_sym
      #     @model = @model.left_joins(lvalue_model) if @model.klass.reflect_on_association(lvalue_model)
      #   end
      # end

      # if @filter
      #   parsed_filter = RKelly::Parser.new.parse(@filter.gsub('like', ' | '))&.to_ecma
      #   return '' unless parsed_filter

      #   @model.klass.defined_enums.values.reduce(:merge)&.each { |k, v| parsed_filter.gsub!("= #{k}", "= #{v}") }
      #   transformed_filter = parsed_filter.gsub(' | ', ' ilike ').gsub('||', 'OR').gsub('&&', 'AND').gsub('===', '=').gsub('==', '=').gsub(
      #     '!= null', 'IS NOT NULL'
      #   ).gsub('= null', 'IS NULL').delete(';')
      #   to_join = transformed_filter.split(/AND|OR|like|ilike/).map do |expression|
      #     expression.strip.split(/!=|=|IS/).first.strip
      #   end.select { |e| e.include?('.') }.map { |e| e.split('.').first }.map(&:to_sym)
      #   to_join.reject { |j| j.to_s.pluralize.to_sym == @model.klass.to_s.pluralize.underscore.to_sym }.each do |j|
      #     @model = @model.left_joins(j).distinct
      #   end
      #   transformed_filter = transformed_filter.split(/(AND|OR|like|ilike)/).map do |e|
      #     arr = e.split(/(!=|=|IS)/)
      #     if arr.first.include?('.')
      #       arr.first.split('.').first.pluralize + '.' + arr.first.split('.').last + arr[1].to_s + arr[2].to_s
      #     else
      #       arr.join
      #     end
      #   end.join
      #   puts ('------------------')
      #   puts ("SQL: #{@model.where(transformed_filter).to_sql}")
      #   puts ('------------------')
      #   @model = @model.where(transformed_filter)
      # end
    end

    def transform_order
      sign = @order_by.split(' ').last.downcase == 'desc' ? 'desc' : 'asc'
      column = @order_by.split(' ').first.strip
      return if invalid_format(column)

      if column.include?('.')
        @model = @model.left_joins(column.split('.').first.to_sym)
        string_type = %i[string text].include?(
          evaluate_model(@model, column.split('.').first).columns_hash[column.split('.').last]&.type
        )
        column = "#{column.split('.').first.pluralize}.#{column.split('.').last}"
        @model = @model.order(Arel.sql("#{string_type ? "upper(#{column})" : column} #{sign}"))
      elsif @order_by
        if %i[string text].include?(@model.columns_hash[column]&.type)
          ordered_by = "upper(#{model_name}.#{column}) #{sign}"
        else
          ordered_by = "#{model_name}.#{column} #{sign}"
        end
        @model = @model.order(ordered_by)
      end
    end

    def invalid_format(str)
      # TODO. check str to ensure it is safe (match alphanum || alpha.alpha || '*' || "*")
      # return false if string.match(/\A[a-z0-9\.\'\"]*\z/)
      # Rails.logger.error("Invalid format string detect : #{str}")
      false
    end

    # def filter_and_order
    #   puts ('------------------')
    #   puts (@filter)
    #   puts ('------------------')
#
    #   if @filter
    #     # Handle enum, transform js to sql operators
    #     transformed_filter = transform_filter(@filter)
    #     # Split on operator, pseudo strip on left / right values + detect some table to join if . is present
    #     to_join = transformed_filter.split(/AND|OR|like|ilike/).map do |expression|
    #       expression.strip.split(/!=|=|IS/).first.strip
    #     end.select { |e| e.include?('.') }.map { |e| e.split('.').first }.map(&:to_sym)
    #     # Left join on associated tables != than model
    #     to_join.reject { |j| j.to_s.pluralize.to_sym == @model.klass.to_s.pluralize.underscore.to_sym }.each do |j|
    #       @model = @model.left_joins(j).distinct
    #     end
#
    #     # Split on operators
    #     transformed_filter = transformed_filter.split(/(AND|OR|like|ilike)/).map do |e|
    #       # Re split on operators != = IS
    #       arr = e.split(/(!=|=|IS)/)
    #       # If left value contains a dot
    #       if arr.first.include?('.')
    #         # Pluralize the table name
    #         arr.first.split('.').first.pluralize + '.' + arr.first.split('.').last + arr[1].to_s + arr[2].to_s
    #       else
    #         arr.join
    #       end
    #     end.join
    #     puts ('------------------')
    #     puts ("SQL: #{@model.where(transformed_filter).to_sql}")
    #     puts ('------------------')
    #     @model = @model.where(transformed_filter)
    #   end
#
    #   return unless @order_by
#
    #   # There is an order by arg
    #   # Find sign and column
    #   sign = @order_by.split(' ').last.downcase == 'desc' ? 'desc' : 'asc'
    #   column = @order_by.split(' ').first
#
    #   if column.include?('.')
    #     # Order on association => Left joins on the associated table
    #     @model = @model.left_joins(column.split('.').first.to_sym)
    #     # Find the type of the field to order on
    #     string_type = %i[string text].include?(
    #       evaluate_model(@model, column.split('.').first).columns_hash[column.split('.').last]&.type
    #     )
    #     # If string type upper case the column
    #     @to_select_to_add = if string_type
    #                           "upper(#{column.split('.').first.pluralize}.#{column.split('.').last})"
    #                         else
    #                           column.split('.').first.pluralize + '.' + column.split('.').last
    #                         end
    #     # Select field you want to order on
    #     @model = @model.select(@to_select_to_add)
    #     column = "#{column.split('.').first.pluralize}.#{column.split('.').last}"
    #     # Order on the column
    #     @model = @model.order(Arel.sql("#{string_type ? "upper(#{column})" : column} #{sign}"))
    #   elsif @order_by
    #     column = "upper(#{model_name}.#{column})" if %i[string text].include?(@model.columns_hash[column]&.type)
    #     @model = @model.order("#{column} #{sign}")
    #   end
    # end
#
    # def transform_filter(filter)
    #   parsed_filter = RKelly::Parser.new.parse(filter.gsub('like', ' | '))&.to_ecma
    #   return '' unless parsed_filter
#
    #   @model.klass.defined_enums.values.reduce(:merge)&.each { |k, v| parsed_filter.gsub!("= #{k}", "= #{v}") }
    #   parsed_filter.gsub(' | ', ' ilike ').gsub('||', 'OR').gsub('&&', 'AND').gsub('===', '=').gsub('==', '=').gsub(
    #     '!= null', 'IS NOT NULL'
    #   ).gsub('= null', 'IS NULL').delete(';')
    # end

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

      hash['id'] = nil if hash['id'].blank?
      fetch_ids_from_relation(hash)

      hash.each_with_object([]) do |(k, v), arr|
        next arr << k if parent_class.new.attributes.key?(k)
        next arr << v if parent_class.new.attributes.key?(v)

        klass = evaluate_model(parent_class, k)
        arr << { k.to_sym => hash_to_array_of_hashes(v, klass) } if klass.present? && v.present?
      end
    end

    def fetch_ids_from_relation(hash)
      hash.select { |k, _| k.ends_with?('_ids') }.each do |(k, _)|
        collection_name = k.gsub('_ids', '').pluralize
        if hash[collection_name].blank?
          hash[collection_name] = { 'id' => nil }
        else
          hash[collection_name]['id'] = nil
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
      fields = fields['edges'].scoped_children.values.first['node']&.scoped_children&.values&.first if fields&.key?('edges')
      return if fields.blank?

      fields.each_with_object({}) do |(k, v), h|
        h[k] = v.scoped_children == {} ? v.definition.name : parse_fields(v)
      end
    end

    def model_name
      @model.class.to_s.split('::').first.underscore.pluralize
    end

  end
end
