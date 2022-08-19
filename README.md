# Graphql Rails Api
`graphql-rails-api` is a wrapper around [graphql-ruby](https://graphql-ruby.org/) for rails application. It describes easily your graphql API in a domain driven design way.

The main purpose of this gem is to earn time providing:
- A normalized code architecture by mapping graphql resources to the active record models
- A global graphql service to directly perform crud mutations
- A set of generators to create or modify graphql resource and active record model at the same time

### Notes
Only postgresql adapter is maintained.
Only model using uuid as identifier are compatible with generated migrations right now.
A model User will be created during installation.

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

### Options
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
Reboot the rails server, and you're good to go!

Now You can perform crud mutation on resources:
```bash
curl -X POST http://localhost:3000/graphql \
  -H "content-type: application/json"      \
  -d '{ "query":"mutation($name: String) { create_city(city: { name: $name }) { name } }", "variables": {"name":"Paris"} }'

=> {"data":{"create_city":{"name":"Paris"}}}
```
You can perform queries as well:
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

To disable propagation (has_many creating the id in the other table, many to many creating the join table and apply to the graphql types), add the option `--no-propagation`
To avoid running migrations after a resource generation, add the option `--no-migrate`


### Note on enum
The library handle enum with an integer column in the model table. Enum is defined into the active record model.
Example:
```bash
$ rails generate graphql_resource house energy_grade:integer belongs_to:user belongs_to:city
```
house.rb
```ruby
class House < ApplicationRecord
  belongs_to :city
  belongs_to :user
  enum energy_grade: {
    good: 0,
    average: 1,
    bad: 2,
  }
end
```

## About queries
3 types of queries are available.

show query:
```gql
query($id: String!) {
  city(id: $id) {
    id
  }
}
```
index query:
A max number of 1000 results are return.
```gql
query($page: String, per_page: String, $filter: String, $order_by: String) {
  cities {
    id
  }
}
```
index query with pagination: Add the suffix `paginated_` to any index query to use pagination
```gql
query($page: String, per_page: String, $filter: String, $order_by: String) {
  paginated_cities {
    id
  }
}
```

### Filter query results
`filter` is a not required string argument used to filter data based on conditions made on active record model fields.
You can use :
- parenthesis : `()`
- Logical operators : `&&` , `||`
- Comparaisons operators : `==`, `!=`, `===`, `!==`, `>`, `<`, `>=`, `<=`

The operators `===` and `!==` are used to perform case sensitive comparaisons on string fields
Example:
The following model is generated
```
rails generate graphql_resource house \
  street:string        \
  number:integer       \
  price:float          \
  energy_grade:integer \
  principal:boolean    \
  belongs_to:user      \
  belongs_to:city
```
The following filter values can be used:
```ruby
"street != 'candlewood lane'"
"street !== 'Candlewood Lane'"
"number <= 50"
"price != 50000"
"build_at <= '#{DateTime.now - 2.years}'"
"user.email == 'jason@gmail.com'"
"city.name != 'Berlin'"
"street != 'candlewood lane' && (city.name != 'Berlin' || user.email == 'jason@gmail.com')"
```

### Order query result argument
`order_by` is a non mandatory string argument used to order the returned data.
With the model above the following order_by values can be used:
```ruby
"street DESC"
"number ASC"
"user.email ASC"
```
## About mutations
The graphql-rails-api application service can handle 5 types of mutation on generated models.

create mutation:
```gql
mutation($name: String!) {
  create_city(
    city: {
      name: $name
    }
  ) {
    id
  }
}
```

update mutation:
```gql
mutation($id: String!, $name: String) {
  update_city(
    id: $id
    city: {
      name: $name
    }
  ) {
    id
    name
  }
}
```

destroy mutation:
```gql
mutation($id: String!) {
  destroy_city(id: $id) {
    id
  }
}
```

bulk_create mutation:
```gql
mutation($cities: [CityInputType]!) {
  bulk_create_city(cities: $cities) {
    id
  }
}
```

bulk_update:
```gql
mutation($cities: [CityInputType]!) {
  bulk_update_city(cities: $cities) {
    id
  }
}
```

You can override the default application service for all mutation by defining your own method into the corresponding graphql service:

Example:

app/graphql/cities/service.rb
```ruby
module Cities
  class Service < ApplicationService
    def create
      return graphql_error('Forbidden') if params[:name] == 'Forbidden city'

      super
    end
  end
end
```
## Custom mutation resource services

To defined your own custom mutation create a file to defined the mutation type and define the correponding methods.

Example:

app/graphql/cities/mutations/custom.rb
```ruby
Cities::Mutations::Custom = GraphQL::Field.define do
  description 'Im a custom mutation'
  type Cities::Type

  argument :id, !types.String
  argument :name, !types.String

  resolve ApplicationService.call(:city, :custom)
end
```

app/graphql/cities/service.rb
```ruby
module Cities
  class Service < ApplicationService
    def custom
      ...
    end
  end
end
```

## About user authentication and scope
TODO.
describe authenticated_user
describe visible_for
describe writable_by

## Graphql API example

Example of a backend API: https://github.com/Poilon/graphql-rails-api-example

## Contributing

You can post any issue, and contribute by making pull requests.
Don't hesitate, even the shortest pull request is great help. <3

Need any help or wanna talk with me on discord : Poilon#5412

## License
The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).
