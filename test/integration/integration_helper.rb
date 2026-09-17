require "test_helper"

class IntegrationRecord < ActiveRecord::Base
  self.abstract_class = true

  include Turbopuffer::ActiveRecord::Schema::Model

  establish_connection(
    adapter: "turbopuffer",
    region: ENV.fetch("TURBOPUFFER_REGION", "gcp-us-central1"),
    api_key: ENV["TURBOPUFFER_API_KEY"],
    namespace_prefix: "activerecord-turbopuffer-adapter-test-#{SecureRandom.hex(4)}"
  )
end

class Doc < IntegrationRecord
  self.table_name = "docs"

  turbopuffer_attribute "id", "uuid"
  turbopuffer_attribute "title", "string", filterable: true, glob: true, regex: true
  turbopuffer_attribute "body", "string", full_text_search: true
  turbopuffer_attribute "views", "int"
  turbopuffer_attribute "published", "bool"
  turbopuffer_attribute "created_at", "datetime"
  turbopuffer_attribute "tags", "[]string"
  turbopuffer_attribute "embedding", "[2]f32", ann: true
end

class Scratch < IntegrationRecord
  self.table_name = "scratch"

  turbopuffer_attribute "id", "uuid"
  turbopuffer_attribute "title", "string"
end

class IntegrationTest < ActiveSupport::TestCase
  setup do
    skip "TURBOPUFFER_API_KEY is not set" unless ENV["TURBOPUFFER_API_KEY"]
  end

  teardown do
    Doc.where(id: Doc.ids).delete_all if Doc.exists?
  end
end

Minitest.after_run do
  if ENV["TURBOPUFFER_API_KEY"]
    Doc.delete_all
    Scratch.delete_all
  end
end
