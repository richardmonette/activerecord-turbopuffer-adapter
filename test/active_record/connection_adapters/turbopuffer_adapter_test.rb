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

  FakeWriteResult = Struct.new(:rows_affected, :rows_remaining)
  FakeQueryResult = Struct.new(:aggregations)

  class FakeNamespace
    attr_reader :writes, :deleted

    def initialize(results = [ FakeWriteResult.new(1, false) ], count: 0)
      @results = results
      @count = count
      @writes = []
      @deleted = false
    end

    def write(args)
      @writes << args
      @results.size > 1 ? @results.shift : @results.first
    end

    def query(args)
      FakeQueryResult.new({ count: @count })
    end

    def delete_all
      @deleted = true
    end

    def last_write = @writes.last
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

  def run_delete(filters, namespace = FakeNamespace.new)
    query = Arel::Visitors::TurbopufferQuery.new(op: :delete, namespace: "items", filters: filters)
    result = Item.with_connection { |connection| connection.turbopuffer_delete(namespace, query) }

    [ namespace, result ]
  end

  def delete_write(filters)
    run_delete(filters).first.last_write
  end

  test "deleting by a single id uses deletes" do
    assert_equal({ deletes: [ "a" ] }, delete_write([ "id", "Eq", "a" ]))
  end

  test "deleting by a list of ids uses deletes" do
    assert_equal({ deletes: [ "a", "b" ] }, delete_write([ "id", "In", [ "a", "b" ] ]))
  end

  test "deleting by another attribute uses delete_by_filter" do
    assert_equal(
      { delete_by_filter: [ "title", "Eq", "walrus" ], delete_by_filter_allow_partial: true },
      delete_write([ "title", "Eq", "walrus" ])
    )
  end

  test "a filtered delete_all keeps deleting while rows remain" do
    namespace = FakeNamespace.new([ FakeWriteResult.new(50_000, true), FakeWriteResult.new(5, false) ])

    _namespace, result = run_delete([ "title", "Eq", "walrus" ], namespace)

    assert_equal 2, namespace.writes.size
    assert_equal 50_005, result.affected_rows
  end

  test "an unfiltered delete_all deletes the namespace and returns the count" do
    namespace = FakeNamespace.new(count: 3)

    _namespace, result = run_delete(nil, namespace)

    assert namespace.deleted
    assert_empty namespace.writes
    assert_equal 3, result.affected_rows
  end

  def run_update(filters, patch, namespace = FakeNamespace.new)
    query = Arel::Visitors::TurbopufferQuery.new(op: :update, namespace: "items", filters: filters, upsert_rows: patch.to_a)
    result = Item.with_connection { |connection| connection.turbopuffer_update(namespace, query) }

    [ namespace, result ]
  end

  test "update_all patches only rows that still need the change" do
    namespace, _result = run_update(nil, { "published" => true })

    assert_equal({
      patch_by_filter: {
        filters: [ "Or", [ [ "published", "NotEq", true ], [ "published", "Eq", nil ] ] ],
        patch: { published: true }
      },
      patch_by_filter_allow_partial: true
    }, namespace.last_write)
  end

  test "a filtered update_all combines the filter with the pending condition" do
    namespace, _result = run_update([ "title", "Eq", "walrus" ], { "published" => true })

    assert_equal [ "And", [
      [ "title", "Eq", "walrus" ],
      [ "Or", [ [ "published", "NotEq", true ], [ "published", "Eq", nil ] ] ]
    ] ], namespace.last_write[:patch_by_filter][:filters]
  end

  test "patching to nil only targets rows that still have a value" do
    namespace, _result = run_update(nil, { "title" => nil })

    assert_equal [ "Or", [ [ "title", "NotEq", nil ] ] ], namespace.last_write[:patch_by_filter][:filters]
  end

  test "update_all keeps patching while rows remain" do
    namespace = FakeNamespace.new([ FakeWriteResult.new(50_000, true), FakeWriteResult.new(10, false) ])

    _namespace, result = run_update(nil, { "published" => true }, namespace)

    assert_equal 2, namespace.writes.size
    assert_equal 50_010, result.affected_rows
  end

  test "update_all raises when a patch makes no progress" do
    namespace = FakeNamespace.new([ FakeWriteResult.new(0, true) ])

    assert_raises(ActiveRecord::StatementInvalid) do
      run_update(nil, { "published" => true }, namespace)
    end
  end

  test "the adapter reports upsert support" do
    Item.with_connection do |connection|
      assert connection.supports_insert_on_duplicate_skip?
      assert connection.supports_insert_on_duplicate_update?
    end
  end
end
