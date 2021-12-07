# GraphqlRailsApi

`graphql-rails-api` is a gem that provides generators to describe easily your graphql API in a domain driven design way.

Need any help or wanna talk with me about it on discord : Poilon#5412

## Installation

Create a rails app via
```
rails new project-name --api --database=postgresql
cd project-name
bundle
rails db:create
```

Add these lines to your application's Gemfile:
```ruby
gem 'graphql-rails-api'
```

And then execute:
```bash
$ bundle
$ rails generate graphql_rails_api:install
```

To disable PostgreSQL uuid extension, add the option `--no-pg-uuid`

To disable ActionCable websocket subscriptions, add the option `--no-action-cable-subs`

To disable Apollo compatibility, add the option `--no-apollo-compatibility`

Automatically, `post '/graphql', to: 'graphql#execute'` will be added to your `config/route.rb`
To avoid this, you can just add the option `--no-generate-graphql-route`

# Usage

## Resources generation

```bash
$ rails generate graphql_resource resource_name field1:string field2:float belongs_to:other_resource_name has_many:other_resources_name many_to_many:other_resources_name
```

To disable migration generation, add the option `--no-migration`

To disable model generation, add the option `--no-model`

To disable mutations generation, add the option `--no-mutations`

To disable service generation, add the option `--no-service`

To disable graphql-type generation, add the option `--no-graphql-type`

To disable graphql-input-type generation, add the option `--no-graphql-input-type`

To disable propagation (has_many creating the id in the other table, many to many creating the join table, and apply to the graphql types), add the option `--no-propagation`

I made the choice of migrate automatically after generating a resource, to avoid doing it each time.
You can of course disable the automatic migrate by adding the option `--no-migrate`

## On generating resources

```bash
$ rails generate graphql_resource computer code:string price:integer power_bench:float belongs_to:user has_many:hard_drives many_to_many:tags
```

This line will create the data migration, the model and the graphql type of the Computer resource.

It will automatically add `has_many :computers` to the User model

It will add a `computer_id` to the `HardDrive` model, and
respectively the `has_many :hard_drives` and `belongs_to :computer` to the `Computer` and `HardDrive` models.

The `many_to_many` option will make the `has_many through` association and create the join table between tag and computer.

All of these relations will be propagated to the graphql types.



## Graphql API example

Example of a backend API: https://github.com/Poilon/graphql-rails-api-example



## Contributing

You can post any issue, and contribute by making pull requests.
Don't hesitate, even the shortest pull request is great help. <3

## License
The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).
