# We don't have any Gemfile in the dummy app
# We use the one provided by the the graphql-rails-api repository
ENV['BUNDLE_GEMFILE'] ||= File.expand_path('../../../../Gemfile', __dir__)
require 'bundler/setup' if File.exist?(ENV['BUNDLE_GEMFILE'])
$LOAD_PATH.unshift File.expand_path('../../../lib', __dir__)
