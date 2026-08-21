require "test_helper"

class Turbopuffer::RailsTest < Minitest::Test
  def test_that_it_has_a_version_number
    refute_nil ::Turbopuffer::Rails::VERSION
  end
end
