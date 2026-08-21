require "test_helper"

class Turbopuffer::Rails::Schema::ModelTest < ActiveSupport::TestCase
  setup { @models = [] }

  def build_model(class_name, parent: TestRecord, table_name: nil, &block)
    Class.new(parent) do
      define_singleton_method(:name) { class_name }
      self.table_name = table_name if table_name
      class_eval(&block) if block
    end.tap { |model| @models << model }
  end

  test "derives the namespace from a multi-word model name" do
    build_model("BlogPost") { turbopuffer_attribute "id", "string" }

    assert_equal "blog_posts", ::Turbopuffer::Rails::Schema::Model.for_table("blog_posts").table_name
  end

  test "respects a table_name assigned above the attributes" do
    build_model("EarlyTableName", table_name: "assigned_first") do
      turbopuffer_attribute "id", "string"
    end

    assert_equal "assigned_first", ::Turbopuffer::Rails::Schema::Model.for_table("assigned_first").table_name
  end

  test "respects a table_name assigned below the attributes" do
    build_model("LateTableName") do
      turbopuffer_attribute "id", "string"
      self.table_name = "assigned_afterwards"
    end

    assert_equal "assigned_afterwards", ::Turbopuffer::Rails::Schema::Model.for_table("assigned_afterwards").table_name
  end

  test "declaring an attribute twice does not duplicate it" do
    model = build_model("Redeclared") do
      turbopuffer_attribute "id", "string"
      turbopuffer_attribute "id", "string"
    end

    assert_equal [ "id" ], model.turbopuffer_attributes.map(&:name)
  end

  test "a subclass does not leak its attributes into the parent" do
    parent = build_model("LeakParent") { turbopuffer_attribute "id", "string" }
    child = build_model("LeakChild", parent:) { turbopuffer_attribute "extra", "string" }

    assert_equal [ "id" ], parent.turbopuffer_attributes.map(&:name)
    assert_equal [ "id", "extra" ], child.turbopuffer_attributes.map(&:name)
  end

  test "a model with no declared attributes is not a namespace" do
    model = build_model("NotANamespace")

    assert_not model.turbopuffer_namespace?
    assert_not_includes ::Turbopuffer::Rails::Schema::Model.namespaces, model
  end

  test "the schema hash carries the index options" do
    model = build_model("Indexed") do
      turbopuffer_attribute "id", "string"
      turbopuffer_attribute "body", "string", filterable: true, full_text_search: true
      turbopuffer_attribute "embedding", "[2]f32", ann: true, distance_metric: "cosine_distance"
    end

    assert_equal({
      "id" => { type: "string" },
      "body" => { type: "string", filterable: true, full_text_search: true },
      "embedding" => { type: "[2]f32", ann: true }
    }, model.turbopuffer_schema_hash)

    assert_equal "cosine_distance", model.turbopuffer_distance_metric
  end

  test "an unregistered namespace raises with a useful message" do
    error = assert_raises(::Turbopuffer::Rails::Schema::UnknownNamespace) do
      ::Turbopuffer::Rails::Schema::Model.for_table("nope")
    end

    assert_match "nope", error.message
  end
end
