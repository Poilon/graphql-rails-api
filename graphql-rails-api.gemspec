$LOAD_PATH.push File.expand_path('../lib', __FILE__)

# Maintain your gem's version:
require 'graphql/rails/api/version'

# Describe your gem and declare its dependencies:
Gem::Specification.new do |s|
  s.name        = 'graphql-rails-api'
  s.version     = Graphql::Rails::Api::VERSION
  s.authors     = ['poilon']
  s.email       = ['poilon@gmail.com']
  s.homepage    = ''
  s.summary     = 'Graphql rails api framework to create easily graphql api with rails'
  s.description = 'Graphql rails api framework to create easily graphql api with rails'
  s.license     = 'MIT'

  s.files = Dir['{app,config,db,lib}/**/*', 'MIT-LICENSE', 'Rakefile', 'README.md']

  s.add_dependency 'graphql'
  s.add_dependency 'rails', '~> 5.1.4'

  s.add_development_dependency 'sqlite3'
end
