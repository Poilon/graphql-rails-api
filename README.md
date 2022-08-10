# GraphqlRailsApi

`graphql-rails-api` is a wrapper around (graphql-ruby)[https://graphql-ruby.org/] for rails application. It provides a global service for all the graphql resources present in the application. It also comes with handy generators to integrate new resources to the graphql schemas.


### Dependencies
TODO.
rails

A model User

gem pg

uuid ?

## Installation

Add the gem to your application's Gemfile:
```ruby
gem 'graphql-rails-api'
```

Download and install the gem:
```bash
$ bundle
$ rails generate graphql_rails_api:install
```

### options
The following options to the `graphql_rails_api:install` command are available:

To disable PostgreSQL uuid extension, add the option `--no-pg-uuid`

To disable ActionCable websocket subscriptions, add the option `--no-action-cable-subs`

To disable Apollo compatibility, add the option `--no-apollo-compatibility`

To avoid the addition of a new post '/graphql' route , add the option `--no-generate-graphql-route`

## Get Started

Generate a new active record model with its graphql type and input type.
```bash
$ rails generate graphql_resource city name:string
```
Reboot the rails server and you're good to go !


Now You can perform mutation on resources :
```bash
curl -X POST http://localhost:3000/graphql \
  -H "content-type: application/json"      \
  -d '{ "query":"mutation($name: String) { create_city(city: { name: $name }) { name } }", "variables": {"name":"Paris"} }'

=> {"data":{"create_city":{"name":"Paris"}}}
```
You can perform queries as well :
```bash
curl -X POST http://localhost:3000/graphql \
  -H "content-type: application/json"       \
  -d '{ "query": "{ cities { name } }" }'

=> {"data":{"cities":[ {"name":"Paris"} ] } }
```

## Generators

```bash
$ rails generate graphql_resource computer code:string price:integer power_bench:float belongs_to:user has_many:hard_drives many_to_many:tags
```

This line will create the data migration, the model and the graphql type of the Computer resource.

It will automatically add `has_many :computers` to the User model

It will add a `computer_id` to the `HardDrive` model, and
respectively the `has_many :hard_drives` and `belongs_to :computer` to the `Computer` and `HardDrive` models.

The `many_to_many` option will make the `has_many through` association and create the join table between tag and computer.

All of these relations will be propagated to the graphql types.

### Options

To disable migration generation, add the option `--no-migration`

To disable model generation, add the option `--no-model`

To disable mutations generation, add the option `--no-mutations`

To disable service generation, add the option `--no-service`

To disable graphql-type generation, add the option `--no-graphql-type`

To disable graphql-input-type generation, add the option `--no-graphql-input-type`

To disable propagation (has_many creating the id in the other table, many to many creating the join table, and apply to the graphql types), add the option `--no-propagation`

To avoid running migrations after a resource generation, add the option `--no-migrate`

## About queries
TODO.
2 different query available
- Individual resource query ... argument id ...
- Multiple resource query ... page per_page filter order_by

## About mutations
create
update
destroy
bulk_create
bulk_update

## About user authentication and scope
TODO.
describe authenticated_user
describe visible_for

## Custom resource services
TODO. explain how to define its own custom service

## Graphql API example

Example of a backend API: https://github.com/Poilon/graphql-rails-api-example

## Contributing

You can post any issue, and contribute by making pull requests.
Don't hesitate, even the shortest pull request is great help. <3

Need any help or wanna talk with me on discord : Poilon#5412

## License
The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).
