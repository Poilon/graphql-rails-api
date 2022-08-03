module Graphql
  module Rails
    module Api
      class Config

        include Singleton

        def self.query_resources
          Dir.glob("#{rails_root}/app/graphql/*/type.rb").map do |dir|
            dir.split('/').last(2).first
          end
        end

        def self.mutation_resources
          mutations = Dir.glob("#{rails_root}/app/graphql/*/mutations/*.rb").reject do |e|
            e.end_with?('type.rb', 'types.rb')
          end
          mutations = mutations.map { |e| e.split('/').last.gsub('.rb', '') }.uniq
          mutations.each_with_object({}) do |meth, h|
            h[meth] = Dir.glob("#{rails_root}/app/graphql/*/mutations/#{meth}.rb").map do |dir|
              dir.split('/').last(3).first
            end
          end
        end

        def self.rails_root
          # File.expand_path('.')
          ::Rails.root
        end
      end
    end
  end
end
