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
    turbopuffer_attribute "payload", "bytes"
    turbopuffer_attribute "quantized", "[2]i8"
    turbopuffer_attribute "terms", "{}f16"
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

  test "bytes serialize as base64 and deserialize back to binary" do
    type = Typed.type_for_attribute("payload")
    raw = "hi\x00there".b

    assert_equal "aGkAdGhlcmU=", type.serialize(raw)
    assert_equal raw, type.deserialize("aGkAdGhlcmU=")
  end

  test "integer vectors cast components to integers" do
    assert_equal [ 1, -2 ], Typed.new(quantized: [ "1", -2.0 ]).quantized
  end

  test "integer vectors reject fractional components" do
    assert_raises(ArgumentError) { Typed.new(quantized: [ 1.5, 2 ]).quantized }
  end

  test "sparse vectors serialize with string keys and float weights" do
    assert_equal({ "a" => 0.5, "b" => 1.0 }, Typed.type_for_attribute("terms").serialize({ a: "0.5", "b" => 1 }))
  end

  test "sparse vectors deserialize with string keys" do
    assert_equal({ "a" => 0.5 }, Typed.type_for_attribute("terms").deserialize({ a: 0.5 }))
  end

  test "a sparse vector attribute declares sparse_knn in the schema" do
    assert_equal({ type: "{}f16", sparse_knn: { distance_metric: "dot_product" } }, Typed.turbopuffer_schema_hash["terms"])
  end

  test "gated and unsupported type strings raise at declaration" do
    [ "[][2]f32", "[]bytes", "[2]f64" ].each do |type|
      assert_raises(ArgumentError) { Class.new(TestRecord) { turbopuffer_attribute "x", type } }
    end
  end

  test "an unknown type raises at declaration" do
    assert_raises(ArgumentError) do
      Class.new(TestRecord) { turbopuffer_attribute "title", "strng" }
    end
  end
end
