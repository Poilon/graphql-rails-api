module Graphql
  class HydrateQuery

    def initialize(model, context, check_visibility: true, id: nil, user: nil)
      @fields = context&.irep_node&.scoped_children&.values&.first
      @model = model
      @models = [model_name.singularize.camelize]
      @check_visibility = check_visibility
      @id = id
      @user = user
    end

    def run
      @model = @model.where(id: @id) if @id
      plucked = @model.deep_pluck(*hash_to_array_of_hashes(parse_fields(@fields), @model))
      result = plucked_attr_to_structs(plucked, model_name.singularize.camelize.constantize)
      @id ? result.first : result
    end

    def plucked_attr_to_structs(arr, parent_model)
      arr.map { |e| hash_to_struct(e, parent_model) }
    end

    def hash_to_struct(hash, parent_model)
      return if !visibility_hash[parent_model].include?(hash['id']) && @check_visibility
      hash.each_with_object(OpenStruct.new) do |(k, v), struct|
        next struct[k.to_sym] = plucked_attr_to_structs(v, evaluate_model(parent_model, k)) if v.is_a?(Array)
        next struct[k.to_sym] = hash_to_struct(v, evaluate_model(parent_model, k)) if v.is_a?(Hash)
        struct[k.to_sym] = v
      end
    end

    def visibility_hash
      @visibility_hash ||= @models.each_with_object({}) do |model, hash|
        hash[model.constantize] = model.constantize.visible_for(user: @user).pluck(:id)
      end
    end

    def hash_to_array_of_hashes(hash, parent_class)
      return if parent_class.nil?
      hash['id'] = nil if hash['id'].blank?
      hash.each_with_object([]) do |(k, v), arr|
        next arr << k if v.blank? && parent_class.new.attributes.key?(k)
        klass = evaluate_model(parent_class, k)
        @models << klass.to_s unless @models.include?(klass.to_s)
        arr << { k.to_sym => hash_to_array_of_hashes(v, klass) } if klass.present? && v.present?
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
      child_class_name = child.to_s.singularize.camelize
      parent_class_name = parent.to_s.singularize.camelize
      return child_class_name.constantize if activerecord_model?(child_class_name)
      return unless activerecord_model?(parent_class_name)
      parent_class_name.constantize.reflections[child.to_s.underscore]&.klass
    end

    def parse_fields(fields)
      fields.each_with_object({}) do |(k, v), h|
        h[k] = v.scoped_children == {} ? nil : parse_fields(v.scoped_children.values.first)
      end
    end

    def model_name
      @model.class.to_s.split('::').first.underscore.pluralize
    end

  end
end
