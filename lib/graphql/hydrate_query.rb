require 'deep_pluck'
require 'rkelly'

module Graphql
  class HydrateQuery

    def initialize(model, context, order_by: nil, filter: nil, check_visibility: true, id: nil, user: nil)
      @context = context
      @filter = filter
      @order_by = order_by
      @model = model
      @models = [model_name.singularize.camelize]
      @check_visibility = check_visibility
      @id = id
      @user = user
    end

    def run
      @model = @model.where(transform_filter(@filter)) if @filter
      @model = @model.order(@order_by) if @order_by
      @model = @model.where(id: @id) if @id
      plucked = @model.deep_pluck(*hash_to_array_of_hashes(parse_fields(@context&.irep_node), @model))
      result = plucked_attr_to_structs(plucked, model_name.singularize.camelize.constantize)&.compact
      @id ? result.first : result
    end

    def transform_filter(filter)
      parsed_filter = RKelly::Parser.new.parse(filter.gsub('like', ' | ')).to_ecma
      parsed_filter.gsub(' | ', ' like ').
        gsub('||', 'OR').gsub('&&', 'AND').gsub('===', '=').gsub('==', '=').delete(';')
    end

    def plucked_attr_to_structs(arr, parent_model)
      arr.map { |e| hash_to_struct(e, parent_model) }
    end

    def hash_to_struct(hash, parent_model)
      return if @check_visibility && !visibility_hash[parent_model]&.include?(hash['id'])

      hash.each_with_object(OpenStruct.new) do |(k, v), struct|
        m = evaluate_model(parent_model, k)
        next struct[k.to_sym] = plucked_attr_to_structs(v, m) if v.is_a?(Array) && m

        next struct[k.to_sym] = hash_to_struct(v, m) if v.is_a?(Hash) && m

        struct[k.to_sym] = v
      end
    end

    def visibility_hash
      @visibility_hash ||= @models.reject(&:blank?).each_with_object({}) do |model, hash|
        visible_ids = model.constantize.visible_for(user: @user)&.pluck(:id)
        next if visible_ids.blank?

        hash[model.constantize] = visible_ids
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
        @models << klass.to_s unless @models.include?(klass.to_s)
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
      if fields.key?('edges')
        fields = fields['edges'].scoped_children.values.first['node']&.scoped_children&.values&.first
      end
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
