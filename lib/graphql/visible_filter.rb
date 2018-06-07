module Graphql
  class VisibilityHash

    def initialize(joins, user)
      @joins = joins
      @user = user
    end

    def run
      fetch_models(@joins).each_with_object({}) do |model, hash|
        hash[model.to_s.underscore.to_sym] = model.visible_for(user: @user).pluck(:id)
      end
    end

    def fetch_models(hash)
      model_names = hash.each_with_object([]) do |(k, v), keys|
        keys << k
        keys.concat(fetch_models(v)) if v.is_a? Hash
      end.map { |m| m.to_s.singularize.camelize }.uniq
      model_names.select do |m|
        Object.const_defined?(m) && m.constantize.ancestors.include?(ActiveRecord::Base)
      end.map(&:constantize)
    end

  end
end
