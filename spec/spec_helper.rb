#require 'dotenv/load' # <============= 1
#require 'simplecov'
#SimpleCov.start 'rails' do # <============= 2
#  add_filter 'spec/'
#  add_filter '.github/'
#  add_filter 'lib/generators/templates/'
#  add_filter 'lib/lokalise_rails/version'
#end
#if ENV['CI'] == 'true' # <============= 3
#  require 'codecov'
#  SimpleCov.formatter = SimpleCov::Formatter::Codecov
#end
# Dir["#{File.dirname(__FILE__)}/support/**/*.rb"].sort.each { |f| require f } # <============= 4
# ENV['RAILS_ENV'] = 'test' # <============= 5
# require_relative '../spec/dummy/config/environment' # <============= 6
# ENV['RAILS_ROOT'] ||= "#{File.dirname(__FILE__)}../../../spec/dummy" # <============= 7