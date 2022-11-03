$LOAD_PATH.push File.expand_path('lib', __dir__)

# Maintain your gem's version:
require 'graphql/rails/api/version'

# Describe your gem and declare its dependencies:
Gem::Specification.new do |s|
  s.name        = 'graphql-rails-api'
  s.version     = Graphql::Rails::Api::VERSION
  s.authors     = ['poilon']
  s.email       = ['poilon@gmail.com']
  s.homepage    = 'https://github.com/poilon/graphql-rails-api'
  s.summary     = 'Graphql rails api framework to create easily graphql api with rails'
  s.description = 'This gem purpose is to make graphql easier to use in ruby. Mainly developed for from-scratch app'
  s.license     = 'MIT'

  s.files = Dir['{app,config,db,lib}/**/*', 'MIT-LICENSE', 'Rakefile', 'README.md']

  s.add_dependency 'graphql', '~> 2.0.15', '<= 2.0.15'
  s.add_runtime_dependency 'deep_pluck_with_authorization', '~> 1.1.3'
  s.add_runtime_dependency 'rails', '~> 7.0.0', '>= 6.1.4'

  s.add_runtime_dependency 'rkelly-remix', '~> 0'
end
