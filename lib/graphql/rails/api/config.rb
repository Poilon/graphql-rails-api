module Graphql
  module Rails
    module Api
      class Config

        include Singleton
        attr_accessor :id_type

        def self.query_resources
          Dir.glob("#{File.expand_path('.')}/app/graphql/*/type.rb").map do |dir|
            dir.split('/').last(2).first
          end
        end

        def self.mutation_resources
          mutations = Dir.glob("#{File.expand_path('.')}/app/graphql/*/mutations/*.rb").reject do |e|
            e.end_with?('type.rb', 'types.rb')
          end
          mutations = mutations.map { |e| e.split('/').last.gsub('.rb', '') }.uniq
          mutations.each_with_object({}) do |meth, h|
            h[meth] = Dir.glob("#{File.expand_path('.')}/app/graphql/*/mutations/#{meth}.rb").map do |dir|
              dir.split('/').last(3).first
            end
          end
        end

      end
    end
  end
end
