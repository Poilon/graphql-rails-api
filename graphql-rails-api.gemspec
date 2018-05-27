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

  s.add_dependency 'graphql', '~> 1.7'
  s.add_dependency 'rails', '~> 5.1'

end
