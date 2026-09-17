require "test_helper"

class TurbopufferTypeMapTest < ActiveSupport::TestCase
  class Typed < TestRecord
    self.table_name = "typed"

    turbopuffer_attribute "id", "uuid", not_null: 1
    turbopuffer_attribute "title", "string"
    turbopuffer_attribute "views", "int"
    turbopuffer_attribute "bytes", "uint"
    turbopuffer_attribute "score", "float"
    turbopuffer_attribute "ratings", "[]float"
    turbopuffer_attribute "published", "bool"
    turbopuffer_attribute "created_at", "datetime"
    turbopuffer_attribute "tags", "[]string"
    turbopuffer_attribute "seen_at", "[]datetime"
    turbopuffer_attribute "embedding", "[2]f32"
  end

  test "bool casts form params" do
    assert_equal true, Typed.new(published: "1").published
    assert_equal false, Typed.new(published: "0").published
  end

  test "a bool filter is cast" do
    query, _binds = Arel::Visitors::Turbopuffer.new.compile(Typed.where(published: "1").arel.ast)

    assert_equal [ "published", "Eq", true ], query.filters
  end

  test "int accepts 64-bit values" do
    assert_equal 2**40, Typed.type_for_attribute("views").serialize(2**40)
  end

  test "uint accepts values above the signed range" do
    assert_equal 2**63, Typed.type_for_attribute("bytes").serialize(2**63)
  end

  test "uint rejects negative values" do
    assert_raises(ActiveModel::RangeError) do
      Typed.type_for_attribute("bytes").serialize(-1)
    end
  end

  test "float casts form params" do
    assert_equal 1.5, Typed.new(score: "1.5").score
  end

  test "float arrays cast each element" do
    assert_equal [ 1.5, 2.0 ], Typed.type_for_attribute("ratings").serialize([ "1.5", 2 ])
  end

  test "string arrays cast each element" do
    assert_equal [ "a", "b" ], Typed.new(tags: [ :a, :b ]).tags
  end

  test "datetime arrays serialize as iso8601" do
    serialized = Typed.type_for_attribute("seen_at").serialize([ Time.utc(2015, 1, 20) ])

    assert_equal [ "2015-01-20T00:00:00Z" ], serialized
  end

  test "a scalar on an array attribute serializes through the element type" do
    assert_equal "walrus", Typed.type_for_attribute("tags").serialize("walrus")
    assert_equal "2015-01-20T00:00:00Z", Typed.type_for_attribute("seen_at").serialize(Time.utc(2015, 1, 20))
  end

  test "datetime arrays deserialize to times" do
    deserialized = Typed.type_for_attribute("seen_at").deserialize([ "2015-01-20T00:00:00Z" ])

    assert_equal [ Time.utc(2015, 1, 20) ], deserialized
  end

  test "vectors cast to floats" do
    assert_equal [ 0.1, 0.2 ], Typed.new(embedding: [ "0.1", "0.2" ]).embedding
  end

  test "a vector with the wrong dimensions raises" do
    assert_raises(ArgumentError) do
      Typed.new(embedding: [ 0.1 ]).embedding
    end
  end

  test "an unknown type raises at declaration" do
    assert_raises(ArgumentError) do
      Class.new(TestRecord) { turbopuffer_attribute "title", "strng" }
    end
  end
end
