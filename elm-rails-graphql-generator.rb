#ruby
#!/usr/bin/env ruby
require 'optparse'
require 'io/console'

options = {}

def show_and_do(str)
  print str.yellow
  show_wait_spinner do
    yield
  end
  puts 'Done!'.green
end

class NilClass
  def blank?
    true
  end
end

class FalseClass
  def blank?
    true
  end
end
class TrueClass
  #   true.blank? # => false
  def blank?
    false
  end
end
class Array
  #   [].blank?      # => true
  #   [1,2,3].blank? # => false
  alias_method :blank?, :empty?
end

class Hash
  #   {}.blank?                # => true
  #   { key: 'value' }.blank?  # => false
  alias_method :blank?, :empty?
end

class String
  def colorize(color_code)
    "\e[#{color_code}m#{self}\e[0m"
  end

  def red
    colorize(31)
  end

  def green
    colorize(32)
  end

  def yellow
    colorize(33)
  end

  def blue
    colorize(34)
  end

  def pink
    colorize(35)
  end

  def light_blue
    colorize(36)
  end
  BLANK_RE = /\A[[:space:]]*\z/

  # A string is blank if it's empty or contains whitespaces only:
  #
  #   ''.blank?       # => true
  #   '   '.blank?    # => true
  #   "\t\n\r".blank? # => true
  #   ' blah '.blank? # => false
  #
  # Unicode whitespace is supported:
  #
  #   "\u00a0".blank? # => true
  #
  def blank?
    # The regexp that matches blank strings is expensive. For the case of empty
    # strings we can speed up this method (~3.5x) with an empty? call. The
    # penalty for the rest of strings is marginal.
    empty? || BLANK_RE.match?(self)
  end
end

def camelcase(str)
  str.split('-').collect(&:capitalize).join
end

def kebabcase(str)
  str.gsub(/([A-Z]+)([A-Z][a-z])/, '\1-\2').
    gsub(/([a-z\d])([A-Z])/, '\1-\2').
    tr('_', '-').
    gsub(/\s/, '-').
    gsub(/__+/, '-').
    downcase
end

def to_valid_file_name(str)
  kebabcase(str).gsub(%r{/[\x00\/\\:\*\?\"<>\|]/}, '-')
end

def yesno
  case $stdin.getch
  when 'Y', 'y' then 't'
  when 'N', 'n' then 'f'
  when 'A', 'a' then 'a'
  else
    puts 'Invalid character.'
    puts 'Type Y for yes or N for no.'
    yesno
  end
end

def clear_console
  system('cls') || system('clear')
end

def show_wait_spinner(fps = 10)
  chars = %w[| / - \\]
  delay = 1.0 / fps
  iter = 0
  spinner = Thread.new do
    while iter
      print chars[(iter += 1) % chars.length]
      sleep delay
      print "\b"
    end
  end
  yield.tap do
    iter = false
    spinner.join
  end
end

abort = false

OptionParser.new do |parser|
  parser.on('-n', '--name NAME', 'The name of your project') do |name|
    options[:name] = name
  end
  parser.on('-p', '--path PATH', 'The path of your project') do |path|
    options[:path] = path
    Dir.mkdir options[:path] unless Dir.exist?(options[:path])
  end
end.parse!

if abort
  puts '...Aborting generation...'
  return
end

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
    print "in #{options[:path]}" unless options[:path].blank?
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
  system("rails new #{options[:name]}-api --api --database=postgresql &> /dev/null")
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

show_and_do('Installing graphql-rails-api...') do
  system('spring stop &> /dev/null')
  system('rails generate graphql_rails_api:install &> /dev/null')
end

show_and_do('Configuring cors (Cross-Origin-Resource-System)...') do
  cors_content =
    %(Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins '*'
    resource '*', headers: :any, methods: %i[get post options]
  end
end)

  File.open('config/initializers/cors.rb', 'a+') { |f| f.write(cors_content) }
end

rails_server = nil

show_and_do('Launch rails server on port 3123...') do
  rails_server = Thread.new {
    system('rails s -p 3123 &> /dev/null')
  }
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

show_and_do('Installing dillonkearns/elm-graphql CLI...') do
  system('npm install --save-dev @dillonkearns/elm-graphql &> /dev/null')
end
camelname = camelcase options[:name]
show_and_do('Configuring package.json...') do
  elm_package_content =
    %({
  "name": "#{options[:name]}",
  "version": "1.0.0",
  "scripts": {
    "api": "elm-graphql http://localhost:3000/graphql --base #{camelname}",
    "rails-graphql-api": "elm-graphql http://localhost:3123/graphql --base #{camelname}"
  }
})

  File.open('package.json', 'w') { |f| f.write(elm_package_content) }
end

show_and_do('Generating elm with dillonkearns/elm-graphql...') do
  system('npm run rails-graphql-api &> /dev/null')
end

show_and_do('Stopping rails server on port 3123...') do
  Thread.kill(rails_server)
end

