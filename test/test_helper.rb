$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "active_record"
require "active_support/test_case"
require "minitest/autorun"

require "turbopuffer/rails"
require "turbopuffer/rails/schema"

Turbopuffer::Rails.register_adapter!

# The adapter never opens a socket until a query is performed, so a pool can be
# established without a server: `connect` is a no-op, `active?` is always true,
# and column definitions come from the model rather than the namespace.
ActiveRecord::Base.establish_connection(adapter: "turbopuffer", database: "test")

class TestRecord < ActiveRecord::Base
  self.abstract_class = true

  include Turbopuffer::Rails::Schema::Model
end
