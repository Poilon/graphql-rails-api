module Graphql
  module Rails
    module Api
      class Config

        include Singleton

        def self.query_resources
          Dir.glob("#{::Rails.root}/app/graphql/*/type.rb").map do |dir|
            dir.split('/').last(2).first
          end
        end

        def self.mutation_resources
          mutations = Dir.glob("#{::Rails.root}/app/graphql/*/mutations/*.rb").reject do |e|
            e.end_with?('type.rb', 'types.rb')
          end
          mutations = mutations.map { |e| e.split('/').last.gsub('.rb', '') }.uniq
          mutations.each_with_object({}) do |meth, h|
            h[meth] = Dir.glob("#{::Rails.root}/app/graphql/*/mutations/#{meth}.rb").map do |dir|
              dir.split('/').last(3).first
            end
          end
        end
      end
    end
  end
end
