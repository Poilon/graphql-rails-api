# frozen_string_literal: true
require 'rails/all'
# require 'rspec/rails'

# require 'factory_girl'
# require 'factory_girl_rails'

# require 'support/dummy/config/environment'
require_relative 'support/dummy/config/environment'
# ActiveRecord::Migration.maintain_test_schema!

# Is a boolean value which controls whether Active Record should
# try to keep your test database schema up-to-date with db/schema.rb
# (or db/structure.sql) when you run your tests. The default is true.
# ActiveRecord::Migration.maintain_test_schema!

# set up db
# be sure to update the schema if required by doing
# - cd spec/rails_app
# - rake db:migrate
# ActiveRecord::Schema.verbose = false
# load 'support/rails_app/db/schema.rb' # use db agnostic schema by default
#
# require 'support/rails_app/factory_girl'
## require 'support/rails_app/factories'
# require 'spec_helper'