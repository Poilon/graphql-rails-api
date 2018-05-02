module Graphql
  class HydrateQuery

    def initialize(model, context, id: nil)
      @fields = context&.irep_node&.scoped_children&.values&.first
      @model = model
      @id = id
    end

    def run
      hash = parse_fields(@fields)
      selectable_values = transform_to_selectable_values(hash)
      joins = remove_keys_with_nil_values(Marshal.load(Marshal.dump(hash)))
      join_model = @model.includes(joins)
      join_model = join_model.where(id: @id) if @id.present?
      res2d = pluck_to_hash_with_ids(join_model, pluckable_attributes(selectable_values))
      joins_with_root = { model_name.to_sym => remove_keys_with_nil_values(Marshal.load(Marshal.dump(hash))) }
      ir = nest(joins_with_root, res2d).first
      @id ? ir_to_output(ir).first : ir_to_output(ir)
    end

    def pluck_to_hash_with_ids(model, keys)
      keys.each do |k|
        resource = k.split('.').first
        keys << "#{resource.pluralize}.id" unless keys.include?("#{resource}.id")
      end
      keys = keys.compact.uniq
      model.pluck(*keys).map do |pa|
        Hash[keys.zip([pa].flatten)]
      end
    end

    def pluckable_attributes(keys)
      db_attributes = keys.uniq.map { |k| k.gsub(/\..*$/, '') }.uniq.map do |resource|
        next unless Object.const_defined?(resource.singularize.camelize)
        resource.singularize.camelize.constantize.new.attributes.keys.map do |attribute|
          "#{resource}.#{attribute}"
        end
      end.flatten.compact
      keys.select { |e| db_attributes.flatten.include?(e) }.map do |e|
        split = e.split('.')
        "#{split.first.pluralize}.#{split.last}"
      end
    end

    def ir_to_output(inter_result)
      model_name = inter_result&.first&.first&.first&.first&.to_s
      if singular?(model_name)
        ir_node_to_output(inter_result.first)
      else
        inter_result.map do |ir_node|
          ir_node_to_output(ir_node) if ir_node
        end
      end
    end

    def ir_node_to_output(ir_node)
      t = ir_node[:results].first.each_with_object({}) do |(attribute, v), h|
        h[attribute.gsub(ir_node.keys.reject { |key| key == :results }.first.first.to_s.pluralize + '.', '')] = v
      end
      relations = ir_node.values&.first&.map { |e| e&.first&.first&.first&.first }
      relations = relations.zip(ir_node[ir_node.keys.reject { |key| key == :results }&.first]).to_h
      relations.map do |key, value|
        t[key] = ir_to_output(value) if value
      end
      Struct.new(*t.keys.map(&:to_sym)).new(*t.values) unless t.keys.blank?
    end

    def singular?(string)
      string.singularize == string
    end

    def nest(joins, res)
      joins.map do |relation_name, other_joins|
        res.group_by do |row|
          [relation_name, row["#{relation_name.to_s.pluralize}.id"]]
        end.map do |k, ungrouped|
          Hash[k, nest(other_joins, ungrouped)].merge(results: extract_values_of_level(k[0], ungrouped).uniq)
        end
      end
    end

    def extract_values_of_level(level, ungrouped)
      ungrouped.map do |row|
        row.select { |k, _| k =~ /#{level.to_s.pluralize}.*/ }
      end
    end

    def transform_to_selectable_values(hash, res = nil)
      @values ||= []
      hash.each do |k, v|
        if v.nil?
          @values << "#{res || model_name}.#{k}" unless activerecord_model?(k)
        else
          next @values << "#{res || model_name}.#{k}" unless activerecord_model?(k)
          transform_to_selectable_values(v, k)
        end
      end
      @values
    end

    def remove_keys_with_nil_values(hash)
      hash.symbolize_keys!
      hash.each_key do |k|
        if hash[k].nil? || !activerecord_model?(k)
          hash.delete(k)
        else
          remove_keys_with_nil_values(hash[k])
        end
      end
    end

    def parse_fields(fields)
      fields.each_with_object({}) do |(k, v), h|
        next if k == '__typename'
        h[k] = v.scoped_children == {} ? nil : parse_fields(v.scoped_children.values.first)
      end
    end

    def model_name
      @model.class.to_s.split('::').first.underscore.pluralize
    end

    def activerecord_model?(name)
      class_name = name.to_s.singularize.camelize
      begin
        class_name.constantize.ancestors.include?(ApplicationRecord)
      rescue NameError
        false
      end
    end

  end
end
