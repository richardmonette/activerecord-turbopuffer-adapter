require "test_helper"

class TurbopufferVisitorTest < ActiveSupport::TestCase
  class Blog < TestRecord
    self.table_name = "blogs"

    turbopuffer_attribute "id", "string", not_null: 1
    turbopuffer_attribute "title", "string"
    turbopuffer_attribute "created_at", "datetime"
  end

  def compile(relation)
    Arel::Visitors::Turbopuffer.new.compile(relation.arel.ast)
  end

  test "offset is not supported" do
    assert_raises NotImplementedError do
      compile(Blog.offset(5))
    end
  end

  test "limit becomes top_k" do
    query, _binds = compile(Blog.limit(3))

    assert_equal 3, query.top_k
  end
end
