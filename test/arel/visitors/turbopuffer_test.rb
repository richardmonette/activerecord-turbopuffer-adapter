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

  test "a single order becomes rank_by" do
    query, _binds = compile(Blog.order(:title))

    assert_equal [ [ "title", "asc" ] ], query.rank_by
  end

  test "multiple orders are not supported" do
    assert_raises NotImplementedError do
      compile(Blog.order(:title).order(:created_at))
    end

    assert_raises NotImplementedError do
      compile(Blog.order(:title, :created_at))
    end
  end

  test "group becomes group_by" do
    query, _binds = compile(Blog.group(:title))

    assert_equal [ "title" ], query.group_by
  end

  test "multiple group attributes are supported" do
    query, _binds = compile(Blog.group(:title, :created_at))

    assert_equal [ "title", "created_at" ], query.group_by
  end

  test "grouped count aggregates per group" do
    blogs = Blog.arel_table
    relation = Blog.group(:title).select(blogs[Arel.star].count.as("count_all"), blogs[:title].as("title"))

    query, _binds = compile(relation)

    assert_equal [ "title" ], query.group_by
    assert_equal [ "count_all", [ "Count" ] ], query.aggregate_by
  end

  test "count without a group has no group_by" do
    query, _binds = compile(Blog.select(Blog.arel_table[Arel.star].count))

    assert_equal [], query.group_by
    assert_equal [ "count_all", [ "Count" ] ], query.aggregate_by
  end

  test "raw SQL is not supported" do
    assert_raises NotImplementedError do
      compile(Blog.where("title = 'hello'"))
    end
  end

  test "joins are not supported" do
    assert_raises NotImplementedError do
      compile(Blog.joins("INNER JOIN posts ON posts.blog_id = blogs.id"))
    end
  end
end
