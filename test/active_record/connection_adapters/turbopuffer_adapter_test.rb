require "test_helper"

class TurbopufferAdapterTest < ActiveSupport::TestCase
  class Item < TestRecord
    self.table_name = "items"

    turbopuffer_attribute "id", "string", not_null: 1
    turbopuffer_attribute "title", "string"
    turbopuffer_attribute "published", "bool", filterable: true
    turbopuffer_attribute "created_at", "datetime"
    turbopuffer_attribute "embedding", "[2]f32", ann: true
  end

  UUID = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/

  FakeWriteResult = Struct.new(:rows_affected)

  class FakeNamespace
    attr_reader :last_write

    def write(args)
      @last_write = args
      FakeWriteResult.new(1)
    end
  end

  def build_query(rows, on_duplicate: :skip)
    Item.with_connection do |connection|
      insert_all = ActiveRecord::InsertAll.new(Item.all, connection, rows, on_duplicate:)
      connection.build_insert_sql(ActiveRecord::InsertAll::Builder.new(insert_all))
    end
  end

  test "insert_all batches every row into one write" do
    query = build_query([
      { title: "walrus", published: true, embedding: [ 0.1, 0.2 ] },
      { title: "narwhal", published: false, embedding: [ 0.3, 0.4 ] }
    ])

    assert_equal :insert, query.op
    assert_equal "items", query.namespace
    assert_equal 2, query.upsert_rows.size
    assert_equal "walrus", query.upsert_rows.first["title"]
    assert_equal [ 0.1, 0.2 ], query.upsert_rows.first["embedding"]
    assert_equal true, query.upsert_rows.first["published"]
  end

  test "a row without an id gets a generated uuid" do
    query = build_query([ { title: "walrus" } ])

    assert_match UUID, query.upsert_rows.first["id"]
  end

  test "a row with a nil id gets a generated uuid" do
    query = build_query([ { id: nil, title: "walrus" } ])

    assert_match UUID, query.upsert_rows.first["id"]
  end

  test "an explicit id is kept" do
    query = build_query([ { id: "existing", title: "walrus" } ], on_duplicate: :update)

    assert_equal "existing", query.upsert_rows.first["id"]
  end

  test "created_at is filled in as an iso8601 timestamp" do
    query = build_query([ { title: "walrus" } ])

    assert_match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\z/, query.upsert_rows.first["created_at"])
  end

  test "an explicit created_at is kept" do
    query = build_query([ { title: "walrus", created_at: Time.utc(2015, 1, 20) } ])

    assert_equal "2015-01-20T00:00:00Z", query.upsert_rows.first["created_at"]
  end

  def delete_write(filters)
    query = Arel::Visitors::TurbopufferQuery.new(op: :delete, namespace: "items", filters: filters)
    namespace = FakeNamespace.new

    Item.with_connection { |connection| connection.turbopuffer_delete(namespace, query) }

    namespace.last_write
  end

  test "deleting by a single id uses deletes" do
    assert_equal({ deletes: [ "a" ] }, delete_write([ [ "id", "Eq", "a" ] ]))
  end

  test "deleting by a list of ids uses deletes" do
    assert_equal({ deletes: [ "a", "b" ] }, delete_write([ [ "id", "In", [ "a", "b" ] ] ]))
  end

  test "deleting by another attribute uses delete_by_filter" do
    assert_equal({ delete_by_filter: [ "title", "Eq", "walrus" ] }, delete_write([ [ "title", "Eq", "walrus" ] ]))
  end

  test "the adapter reports upsert support" do
    Item.with_connection do |connection|
      assert connection.supports_insert_on_duplicate_skip?
      assert connection.supports_insert_on_duplicate_update?
    end
  end
end
