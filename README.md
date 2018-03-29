# GraphqlRailsApi

`graphql-rails-api` is a gem that provide generators to describe easily your graphql API.

## Installation
Add these lines to your application's Gemfile:

```ruby
gem 'graphql'
gem 'graphql-rails-api'
```

And then execute:
```bash
$ bundle
$ rails generate graphql_rails_api:install
```


## Usage

```bash
$ rails generate graphql_resource account base_email:string auth_id:string
$ rails generate graphql_resource user email:string first_name:string last_name:string has_many:users
$ rails generate graphql_resource computer ref:string description:text belongs_to:user
$ rails generate graphql_resource motherboard ref:string many_to_many:computers

```




## Contributing
Contribution directions go here.

## License
The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).
