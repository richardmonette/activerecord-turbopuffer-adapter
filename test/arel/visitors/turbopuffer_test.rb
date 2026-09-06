require "test_helper"

class TurbopufferVisitorTest < ActiveSupport::TestCase
  class Blog < TestRecord
    self.table_name = "blogs"

    turbopuffer_attribute "id", "string", not_null: 1
    turbopuffer_attribute "title", "string"
    turbopuffer_attribute "created_at", "datetime"
    turbopuffer_attribute "embedding", "[2]f32", ann: true
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

  test "rank_by builds a ranking from its arguments" do
    query, _binds = compile(Blog.rank_by("embedding", "ANN", [ 0.1, 0.2 ]).limit(10))

    assert_equal [ [ "embedding", "ANN", [ 0.1, 0.2 ] ] ], query.rank_by
    assert_equal 10, query.top_k
  end

  test "rank_by accepts a full text ranking" do
    query, _binds = compile(Blog.rank_by("title", "BM25", "quick walrus"))

    assert_equal [ [ "title", "BM25", "quick walrus" ] ], query.rank_by
  end

  test "rank_by passes a composed ranking through untouched" do
    ranking = [ "Sum", [
      [ "Product", 2, [ "title", "BM25", "mammal" ] ],
      [ "title", "BM25", "quick walrus" ]
    ] ]

    query, _binds = compile(Blog.rank_by(ranking))

    assert_equal [ ranking ], query.rank_by
  end

  test "rank_by combines with a filter and a limit" do
    relation = Blog.where(title: "walrus").rank_by("embedding", "ANN", [ 0.1, 0.2 ]).limit(5)

    query, _binds = compile(relation)

    assert_equal [ "title", "Eq", "walrus" ], query.filters
    assert_equal [ [ "embedding", "ANN", [ 0.1, 0.2 ] ] ], query.rank_by
    assert_equal 5, query.top_k
  end

  test "two different rankings are not supported" do
    assert_raises NotImplementedError do
      compile(Blog.rank_by("embedding", "ANN", [ 0.1 ]).rank_by("title", "BM25", "walrus"))
    end
  end

  test "a ranking and an attribute order are not supported together" do
    assert_raises NotImplementedError do
      compile(Blog.rank_by("embedding", "ANN", [ 0.1 ]).order(:title))
    end
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

  test "limit on a grouped query caps the groups" do
    blogs = Blog.arel_table
    relation = Blog.group(:title).limit(2).select(blogs[Arel.star].count.as("count_all"), blogs[:title].as("title"))

    query, _binds = compile(relation)

    assert_equal [ "title" ], query.group_by
    assert_equal 2, query.top_k
  end

  test "count without a group has no group_by" do
    query, _binds = compile(Blog.select(Blog.arel_table[Arel.star].count))

    assert_equal [], query.group_by
    assert_equal [ "count_all", [ "Count" ] ], query.aggregate_by
  end

  test "having is not implemented yet" do
    assert_raises NotImplementedError do
      compile(Blog.group(:title).having(Blog.arel_table[Arel.star].count.gt(3)))
    end
  end

  test "distinct is not implemented yet" do
    assert_raises NotImplementedError do
      compile(Blog.distinct)
    end
  end

  test "distinct count is not implemented yet" do
    assert_raises NotImplementedError do
      compile(Blog.select(Blog.arel_table[:title].count(true)))
    end
  end

  test "where with an array becomes an In filter" do
    query, _binds = compile(Blog.where(id: [ "a", "b" ]))

    assert_equal [ "id", "In", [ "a", "b" ] ], query.filters
  end

  test "separate where nodes are and-ed together" do
    blogs = Blog.arel_table
    manager = blogs.where(blogs[:title].eq("walrus")).where(blogs[:created_at].gt("2015-01-20T00:00:00Z")).project(blogs[:id])

    query, _binds = Arel::Visitors::Turbopuffer.new.compile(manager.ast)

    assert_equal [ "And", [
      [ "title", "Eq", "walrus" ],
      [ "created_at", "Gt", "2015-01-20T00:00:00Z" ]
    ] ], query.filters
  end

  test "where.not with an array becomes a NotIn filter" do
    query, _binds = compile(Blog.where.not(id: [ "a", "b" ]))

    assert_equal [ "id", "NotIn", [ "a", "b" ] ], query.filters
  end

  test "an array filter casts its values" do
    query, _binds = compile(Blog.where(created_at: [ Time.utc(2015, 1, 20), Time.utc(2015, 1, 21) ]))

    assert_equal [ "created_at", "In", [ "2015-01-20T00:00:00Z", "2015-01-21T00:00:00Z" ] ], query.filters
  end

  test "an inclusive range becomes a pair of bounds" do
    query, _binds = compile(Blog.where(created_at: Time.utc(2015, 1, 20)..Time.utc(2015, 1, 21)))

    assert_equal [ "And", [
      [ "created_at", "Gte", "2015-01-20T00:00:00Z" ],
      [ "created_at", "Lte", "2015-01-21T00:00:00Z" ]
    ] ], query.filters
  end

  test "an exclusive range excludes its upper bound" do
    query, _binds = compile(Blog.where(created_at: Time.utc(2015, 1, 20)...Time.utc(2015, 1, 21)))

    assert_equal [ "And", [
      [ "created_at", "Gte", "2015-01-20T00:00:00Z" ],
      [ "created_at", "Lt", "2015-01-21T00:00:00Z" ]
    ] ], query.filters
  end

  test "a beginless range becomes a single upper bound" do
    query, _binds = compile(Blog.where(created_at: ..Time.utc(2015, 1, 21)))

    assert_equal [ "created_at", "Lte", "2015-01-21T00:00:00Z" ], query.filters
  end

  test "an endless range becomes a single lower bound" do
    query, _binds = compile(Blog.where(created_at: Time.utc(2015, 1, 20)..))

    assert_equal [ "created_at", "Gte", "2015-01-20T00:00:00Z" ], query.filters
  end

  test "a negated range is pushed down to the operators" do
    query, _binds = compile(Blog.where.not(created_at: Time.utc(2015, 1, 20)..Time.utc(2015, 1, 21)))

    assert_equal [ "Or", [
      [ "created_at", "Lt", "2015-01-20T00:00:00Z" ],
      [ "created_at", "Gt", "2015-01-21T00:00:00Z" ]
    ] ], query.filters
  end

  test "several ranges for one attribute are or-ed together" do
    range = Time.utc(2015, 1, 20)..Time.utc(2015, 1, 21)
    other = Time.utc(2015, 2, 20)..Time.utc(2015, 2, 21)

    query, _binds = compile(Blog.where(created_at: [ range, other ]))

    assert_equal [ "Or", [
      [ "And", [ [ "created_at", "Gte", "2015-01-20T00:00:00Z" ], [ "created_at", "Lte", "2015-01-21T00:00:00Z" ] ] ],
      [ "And", [ [ "created_at", "Gte", "2015-02-20T00:00:00Z" ], [ "created_at", "Lte", "2015-02-21T00:00:00Z" ] ] ]
    ] ], query.filters
  end

  test "a range filter combines with a ranking and a limit" do
    relation = Blog.where(created_at: Time.utc(2015, 1, 20)..).order(created_at: :desc).limit(20)

    query, _binds = compile(relation)

    assert_equal [ "created_at", "Gte", "2015-01-20T00:00:00Z" ], query.filters
    assert_equal [ [ "created_at", "desc" ] ], query.rank_by
    assert_equal 20, query.top_k
  end

  test "a date bound is serialized as midnight UTC" do
    query, _binds = compile(Blog.where(created_at: Date.new(2015, 1, 20)..Date.new(2015, 1, 21)))

    assert_equal [ "And", [
      [ "created_at", "Gte", "2015-01-20T00:00:00Z" ],
      [ "created_at", "Lte", "2015-01-21T00:00:00Z" ]
    ] ], query.filters
  end

  test "a bound in another zone is serialized as UTC" do
    query, _binds = compile(Blog.where(created_at: Time.new(2015, 1, 20, 12, 30, 0, "-05:00")..))

    assert_equal [ "created_at", "Gte", "2015-01-20T17:30:00Z" ], query.filters
  end

  test "the exists? projection selects id" do
    query, _binds = compile(Blog.where(title: "walrus").select(Arel.sql("1 AS one")).limit(1))

    assert_equal [ "id" ], query.include_attributes
    assert_equal 1, query.top_k
  end

  test "raw SQL is not supported" do
    assert_raises NotImplementedError do
      compile(Blog.where("title = 'hello'"))
    end
  end

  test "raw SQL with bind parameters is not supported" do
    assert_raises NotImplementedError do
      compile(Blog.where("created_at > ?", Time.utc(2015, 1, 20)))
    end
  end

  test "joins are not supported" do
    assert_raises NotImplementedError do
      compile(Blog.joins("INNER JOIN posts ON posts.blog_id = blogs.id"))
    end
  end
end
