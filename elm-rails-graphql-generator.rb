# ruby
# !/usr/bin/env ruby
require 'optparse'
require 'io/console'
require_relative 'wait_for_it'
require_relative 'utils'
require_relative 'elm_graphql_administrator'

options = {}
elm_boiler_plate = File.read('boiler_plate.elm')
abort = false

OptionParser.new do |parser|
  parser.on('-n', '--name NAME', 'The name of your project') do |name|
    options[:name] = name
  end
  parser.on('-p', '--path PATH', 'The path of your project') do |path|
    options[:path] = path
    Dir.mkdir options[:path] unless Dir.exist?(options[:path])
  end
  parser.on('--no-pg-uuid', 'Disables PostgreSQL uuid extension') do
    options['--no-pg-uuid'] = true
  end
  parser.on('--no-action-cable-subs', 'Disables ActionCable websocket subscriptions') do
    options['--no-action-cable-subs'] = true
  end
  parser.on('--no-apollo-compatibility', 'Disables Apollo compatibility') do
    options['--no-apollo-compatibility'] = true
  end
  parser.on('--no-users', 'Runs the script with no user migrations') do
    options['--no-users'] = true
  end
end.parse!

clear_console

Dir.chdir options[:path] unless options[:path].blank?

loop do
  if options[:name].blank?
    puts 'What is the name of your project?'
    options[:name] = gets.chomp
  end
  options[:name] = to_valid_file_name options[:name]
  if File.exist?(options[:name])
    clear_console
    puts "The directory #{options[:name]} already exists"
    puts "in : #{options[:path]}" unless options[:path].blank?
    options[:name] = nil
    next
  end
  puts 'The directory created will be ' + options[:name]
  puts 'Is that what you want? Type Y for yes, N for no, A for abort'
  case yesno
  when 't' then break
  when 'f' then
    clear_console
    puts 'Old name : ' + options[:name]
    options[:name] = nil
  when 'a' then
    abort = true
    break
  else raise 'A problem occured, please try launching the script again'
  end
end

if abort
  puts '...Aborting generation...'
  return
end

clear_console

show_and_do("Generating #{options[:name]} api..") do
  Dir.mkdir options[:name]
  Dir.chdir options[:name]
  system("rails new #{options[:name]}-api --database=postgresql &> /dev/null")
end

show_and_do('Adding graphql, graphql-rails-api and rack-cors to the Gemfile...') do
  Dir.chdir options[:name] + '-api'
  system('bundle add graphql --skip-install &> /dev/null')
  system('bundle add graphql-rails-api --skip-install &> /dev/null')
  system('bundle add rack-cors &> /dev/null')
end

show_and_do('Creating database...') do
  system('rails db:create &> /dev/null')
end

concatened_options = (options['--no-pg-uuid'] ? ' --no-pg-uuid' : '') +
  (options['--no-action-cable-subs'] ? ' --no-action-cable-subs' : '') +
  (options['--no-apollo-compatibility'] ? ' --no-apollo-compatibility' : '')

show_and_do("Installing graphql-rails-api#{concatened_options}...") do
  system('spring stop &> /dev/null')
  system("rails generate graphql_rails_api:install #{concatened_options} &> /dev/null")
end

show_and_do('Installing Webpacker') do
  system('spring stop &> /dev/null')
  system('rails webpacker:install &> /dev/null')
end

show_and_do('Configuring cors (Cross-Origin Resource Sharing)...') do
  cors_content =
    %(Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins '*'
    resource '*', headers: :any, methods: %i[get post options]
  end
end)

  File.open('config/initializers/cors.rb', 'a+') { |f| f.write(cors_content) }
end

show_and_do('Launch rails server on port 3123...') do
  WaitForIt.new('rails s -p 3123', wait_for: 'Listening on tcp')
end

show_and_do("Generating #{options[:name]} front in elm...") do
  Dir.mkdir "../#{options[:name]}-front"
  Dir.chdir "../#{options[:name]}-front"
  system("printf 'y' | elm init &> /dev/null")
end

show_and_do('Installing dillonkearns/elm-graphql...') do
  system("printf 'y' | elm install dillonkearns/elm-graphql &> /dev/null")
  system("printf 'y' | elm install elm/json &> /dev/null")
end

show_and_do('Installing elm-athlete/athlete...') do
  system("printf 'y' | elm install elm-athlete/athlete &> /dev/null")
  system("printf 'y' | elm install elm/time &> /dev/null")
  system("printf 'y' | elm install elm/url &> /dev/null")
end

show_and_do('Installing dillonkearns/elm-graphql CLI...') do
  system('npm install --save-dev @dillonkearns/elm-graphql &> /dev/null')
end

show_and_do('Installing elm-live CLI...') do
  system('npm install --save-dev elm-live@next &> /dev/null')
end

camelname = camelcase options[:name]

show_and_do('Configuring package.json...') do
  elm_package_content =
    %({
  "name": "#{options[:name]}",
  "version": "1.0.0",
  "scripts": {
    "api": "elm-graphql http://localhost:3000/graphql --base #{camelname}",
    "rails-graphql-api": "elm-graphql http://localhost:3123/graphql --base #{camelname}",
    "live": "elm-live src/Main.elm -u --open",
    "lived": "elm-live src/Main.elm -u --open -- --debug"
  }
})

  File.open('package.json', 'w') { |f| f.write(elm_package_content) }
end

show_and_do('Generating elm with dillonkearns/elm-graphql...') do
  system('npm run rails-graphql-api &> /dev/null')
end

show_and_do('Generating admin...') do
  generate_admin
end

show_and_do('Copying boiler_plate.elm...') do
  File.open('src/Main.elm', 'w') { |f| f.write(elm_boiler_plate) }
end

show_and_do('Stopping rails server on port 3123...') do
  system("lsof -i :3123 -sTCP:LISTEN | awk 'NR > 1 {print $2}' | xargs kill -9 &> /dev/null")
end

puts "\nSuccessful installation!".green
puts 'You can now, run your rails server and front server:'.green
puts '  rails s'.yellow + " in #{options[:name]}-api".green
puts '  npm run live'.yellow + " in #{options[:name]}-front".green
