# turbopuffer-rails

turbopuffer-rails is an unofficial, fan made Ruby on Rails ActiveRecord database adapter for turbopuffer. If you are looking for the official turbopuffer Ruby gem see: https://github.com/turbopuffer/turbopuffer-ruby

The purpose of this gem is to provide Rails developers a familiar ActiveRecord style interface to turbopuffer.

## Installation

To use this gem, install via Bundler by adding the following to your application's Gemfile:

```ruby
gem 'turbopuffer-rails'
```

## Usage

### Configuration

In `config/database.yml` define a turbopuffer adapter:


```yaml
development:
  adapter: turbopuffer
  region: gcp-us-central1
  api_key: <%= ENV["TURBOPUFFER_API_KEY"] %>
```

Optionally, you can define `namespace_prefix`, which is useful for separating namespace for production and development environments.

### Defining a model

```ruby
class Document < ApplicationRecord
  turbopuffer_attribute "id",        "uuid",   not_null: 1
  turbopuffer_attribute "title",     "string", filterable: true
  turbopuffer_attribute "body",      "string", full_text_search: true
  turbopuffer_attribute "published", "bool",   filterable: true
  turbopuffer_attribute "embedding", "[1536]f32", ann: true
end
```

By default the namespace is the model's table_name, but it can be customized with `self.table_name = "..."` Currently, ids are always UUIDv7 (which sort chronologically, to support pagination.)

The distance metric applies to all vector columns in a namespace and defaults to `cosine_distance`. To use `euclidean_squared` instead, declare it in the model:

```ruby
class Document < ApplicationRecord
  turbopuffer_distance_metric "euclidean_squared"

  turbopuffer_attribute "id",        "uuid",      not_null: 1
  turbopuffer_attribute "embedding", "[1536]f32", ann: true
end
```

### Creating records

```ruby
Document.create!(title: "Hello", body: "...", published: true)

doc = Document.new(title: "Draft")
doc.save!

doc.update!(published: true)
doc.destroy
```

> Note that inserts are treated as upserts, such that writing a row whose id already exists is effectively treated as an update.

> Note that transactions are not supported, interacting with that portion of the ActiveRecord API is no-op

### Querying

```ruby
Document.where(published: true)
Document.where(id: ["a", "b"])
Document.where.not(id: ["a", "b"])
Document.where(created_at: 1.week.ago..)

Document.order(:title).limit(20)
Document.group(:title).count
Document.count
Document.find("018f...")

Document.rank_by("vector", "ANN", query_vector).limit(10)
Document.rank_by("text", "BM25", "quick walrus").limit(10)

Document
  .where(public: true)
  .rank_by(["Sum", [
    ["Product", 2, ["category", "BM25", "mammal"]],
    ["text", "BM25", "quick walrus"],
  ]])
  .limit(10)
```

### Using alongside Postgres

While something of a lark, aspirationally the idea of this gem is to make turbopuffer conveniently usable as the primary db in a Rails app. In practice, however, using turbopuffer alongside a traditional primary db (such as postgres) is a supported, potentially more practical solution.

A dual db approach can be setup as follows:

```yaml
development:
  primary:
    adapter: postgresql
    database: myapp_development
  turbopuffer:
    adapter: turbopuffer
    region: gcp-us-central1
    api_key: <%= ENV["TURBOPUFFER_API_KEY"] %>
    namespace_prefix: myapp-development
```

```ruby
class TurbopufferRecord < ApplicationRecord
  self.abstract_class = true

  connects_to database: { writing: :turbopuffer, reading: :turbopuffer }
end

class Document < TurbopufferRecord
  turbopuffer_attribute "id",   "uuid",   not_null: 1
  turbopuffer_attribute "body", "string", full_text_search: true
end
```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/richardmonette/turbopuffer-rails. As this is an unoffical gem, please do not report bugs upstream.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
