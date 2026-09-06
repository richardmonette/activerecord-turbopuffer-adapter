require "test_helper"

class Turbopuffer::ActiveRecordTest < Minitest::Test
  def test_that_it_has_a_version_number
    refute_nil ::Turbopuffer::ActiveRecord::VERSION
  end
end
