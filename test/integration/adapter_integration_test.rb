require "integration/integration_helper"

class AdapterIntegrationTest < IntegrationTest
  UUID = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/

  def walrus(**attributes)
    Doc.create!({ title: "Walrus", body: "the walrus swims", views: 10, published: true,
                  tags: [ "arctic", "mammal" ], embedding: [ 1.0, 0.0 ] }.merge(attributes))
  end

  def narwhal(**attributes)
    Doc.create!({ title: "Narwhal", body: "the narwhal dives", views: 5, published: false,
                  tags: [ "arctic", "tusk" ], embedding: [ 0.0, 1.0 ] }.merge(attributes))
  end

  test "a record round-trips through create and find" do
    created = walrus

    found = Doc.find(created.id)

    assert_match UUID, found.id
    assert_equal "Walrus", found.title
    assert_equal 10, found.views
    assert_equal true, found.published
    assert_equal [ "arctic", "mammal" ], found.tags
    assert_equal [ 1.0, 0.0 ], found.embedding
    assert_equal created.created_at.to_i, found.created_at.to_i
  end

  test "update and destroy" do
    doc = walrus

    doc.update!(views: 11, published: false)
    reloaded = Doc.find(doc.id)
    assert_equal 11, reloaded.views
    assert_equal false, reloaded.published

    doc.destroy
    assert_raises(ActiveRecord::RecordNotFound) { Doc.find(doc.id) }
  end

  test "equality, list, negation and range filters" do
    walrus
    narwhal

    assert_equal [ "Walrus" ], Doc.where(published: true).pluck(:title)
    assert_equal [ "Narwhal", "Walrus" ], Doc.where(title: [ "Walrus", "Narwhal" ]).pluck(:title).sort
    assert_equal [ "Narwhal" ], Doc.where.not(title: "Walrus").pluck(:title)
    assert_equal [ "Walrus" ], Doc.where(views: 6..).pluck(:title)
    assert_equal [ "Narwhal" ], Doc.where(views: 1...10).pluck(:title)
  end

  test "nil matches documents missing the attribute" do
    walrus
    narwhal(tags: nil)

    assert_equal [ "Narwhal" ], Doc.where(tags: nil).pluck(:title)
    assert_equal [ "Walrus" ], Doc.where.not(tags: nil).pluck(:title)
  end

  test "Lt and Lte match documents missing the attribute" do
    walrus
    narwhal(views: nil)

    assert_equal [ "Narwhal" ], Doc.where(views: ..5).pluck(:title)
    assert_equal [ "Walrus" ], Doc.where(views: 6..).pluck(:title)
  end

  test "glob, case-insensitive glob and regexp" do
    walrus
    narwhal

    assert_equal [ "Walrus" ], Doc.where(title: Doc.glob("Wal*")).pluck(:title)
    assert_equal [], Doc.where(title: Doc.glob("wal*")).pluck(:title)
    assert_equal [ "Walrus" ], Doc.where(title: Doc.glob("wal*", case_sensitive: false)).pluck(:title)
    assert_equal [ "Narwhal" ], Doc.where.not(title: Doc.glob("Wal*")).pluck(:title)
    assert_equal [ "Walrus" ], Doc.where(title: /^Wal/).pluck(:title)
    assert_equal [ "Walrus" ], Doc.where(title: /^wal/i).pluck(:title)
    assert_equal [ "Walrus" ], Doc.where(title: Doc.glob("[VW]alrus")).pluck(:title)
  end

  test "array attributes filter by containment" do
    walrus
    narwhal
    Doc.create!(title: "Seal", body: "the seal rests", embedding: [ 0.5, 0.5 ])

    assert_equal [ "Narwhal", "Walrus" ], Doc.where(tags: "arctic").pluck(:title).sort
    assert_equal [ "Walrus" ], Doc.where(tags: "mammal").pluck(:title)
    assert_equal [ "Narwhal", "Walrus" ], Doc.where(tags: [ "mammal", "tusk" ]).pluck(:title).sort
    assert_equal [ "Narwhal" ], Doc.where(tags: [ "arctic" ]).where.not(tags: "mammal").pluck(:title)
    assert_equal [ "Narwhal", "Seal" ], Doc.where.not(tags: "mammal").pluck(:title).sort
  end

  test "count, sum and grouped count" do
    walrus
    narwhal
    Doc.create!(title: "Seal", body: "the seal rests", embedding: [ 0.5, 0.5 ])

    assert_equal 3, Doc.count
    assert_equal 2, Doc.count(:views)
    assert_equal 15, Doc.sum(:views)
    assert_equal 1, Doc.where(published: true).count
    assert_equal({ "Walrus" => 1, "Narwhal" => 1, "Seal" => 1 }, Doc.group(:title).count)
  end

  test "exists?, any? and empty?" do
    assert_not Doc.exists?
    assert Doc.none?

    walrus

    assert Doc.exists?
    assert Doc.any?
    assert_not Doc.all.empty?
    assert Doc.where(title: "Walrus").exists?
    assert_not Doc.where(title: "Orca").exists?
  end

  test "insert_all writes a batch with generated ids and upsert_all overwrites" do
    Doc.insert_all([
      { title: "Walrus", body: "a", embedding: [ 1.0, 0.0 ] },
      { title: "Narwhal", body: "b", embedding: [ 0.0, 1.0 ] }
    ])

    docs = Doc.all.to_a
    assert_equal 2, docs.size
    assert docs.all? { |doc| doc.id.match?(UUID) }
    assert docs.all? { |doc| doc.created_at.present? }

    id = docs.first.id
    Doc.upsert_all([ { id: id, title: "Renamed", body: "c", embedding: [ 1.0, 0.0 ] } ])

    assert_equal "Renamed", Doc.find(id).title
    assert_equal 2, Doc.count
  end

  test "update_all patches matching rows and narrows to rows still needing the change" do
    walrus
    narwhal

    assert_equal 1, Doc.update_all(published: true)
    assert_equal 0, Doc.update_all(published: true)
    assert_equal [ true, true ], Doc.pluck(:published)

    assert_equal 1, Doc.where(title: "Walrus").update_all(views: 99)
    assert_equal 99, Doc.find_by(title: "Walrus").views
    assert_equal 5, Doc.find_by(title: "Narwhal").views
  end

  test "delete_all by filter and by id list" do
    walrus
    narwhal
    seal = Doc.create!(title: "Seal", body: "the seal rests", embedding: [ 0.5, 0.5 ])

    assert_equal 1, Doc.where(title: "Walrus").delete_all
    assert_equal [ "Narwhal", "Seal" ], Doc.pluck(:title).sort

    assert_equal 1, Doc.where(id: [ seal.id ]).delete_all
    assert_equal [ "Narwhal" ], Doc.pluck(:title)
  end

  test "an unfiltered delete_all clears the namespace" do
    Scratch.create!(title: "one")
    Scratch.create!(title: "two")

    assert_equal 2, Scratch.delete_all
    assert_equal 0, Scratch.count
    assert_equal 0, Scratch.delete_all
  end

  test "rank_by ANN orders by vector distance" do
    walrus
    narwhal

    assert_equal [ "Walrus", "Narwhal" ], Doc.rank_by("embedding", "ANN", [ 0.9, 0.1 ]).limit(2).pluck(:title)
    assert_equal [ "Narwhal", "Walrus" ], Doc.rank_by("embedding", "ANN", [ 0.1, 0.9 ]).limit(2).pluck(:title)
  end

  test "rank_by BM25 finds full-text matches" do
    walrus
    narwhal

    assert_equal [ "Narwhal" ], Doc.rank_by("body", "BM25", "dives").limit(5).pluck(:title)
  end

  test "order, limit and find_each" do
    5.times { |i| Doc.create!(title: "Doc #{i}", body: "b", views: i, embedding: [ 1.0, 0.0 ]) }

    assert_equal [ "Doc 4", "Doc 3" ], Doc.order(views: :desc).limit(2).pluck(:title)

    seen = []
    Doc.find_each(batch_size: 2) { |doc| seen << doc.title }
    assert_equal 5, seen.size
    assert_equal seen.uniq, seen
  end
end
