module Arel::Visitors
  class TurbopufferQuery
    def to_h
      {
        op: @op,
        namespace: @namespace,
        filters: @filters,
        top_k: @top_k,
        rank_by: @rank_by,
        include_attributes: @include_attributes,
        aggregate_by: @aggregate_by,
        upsert_rows: @upsert_rows
      }
    end
    def to_s = JSON.generate(to_h)
    alias inspect to_s
    def hash = to_h.hash
    def eql?(other) = other.is_a?(self.class) && to_h == other.to_h
    alias == eql?

    attr_reader :op, :namespace, :filters, :top_k, :rank_by, :include_attributes, :upsert_rows, :aggregate_by
    attr_accessor :binds

    def initialize(op:, namespace:, filters:, top_k:, rank_by:, include_attributes:, upsert_rows:, aggregate_by: nil)
      @op = op
      @namespace = namespace
      @filters = filters
      @top_k = top_k
      @rank_by = rank_by
      @include_attributes = include_attributes
      @aggregate_by = aggregate_by
      @upsert_rows = upsert_rows

      @binds = []
    end
  end

  class Turbopuffer < Arel::Visitors::Visitor
    def initialize
      super
      @binds = []
    end

    attr_accessor :binds

    def compile(node, _collector = nil, bound_values: nil, collecting_binds: false)
      @binds = []
      @bound_values = bound_values
      @collecting_binds = collecting_binds
      [ visit(node), @binds ]
    ensure
      @bound_values = nil
      @collecting_binds = false
    end

    private

    def conjoin(x)
      x
    end

    def visit_Arel_Nodes_SelectStatement(o)
      raise NotImplementedError, "offset is not supported, filter on a sortable attribute for cursor pagination" if o.offset

      core = o.cores.last

      aggregates, attributes = core.projections.partition { |p| p.class == Arel::Nodes::Count }

      TurbopufferQuery.new(
        op:                 :select,
        namespace:          visit(core.source),
        filters:            conjoin(core.wheres.map { |w| visit(w) }),
        top_k:              o.limit && visit(o.limit),
        rank_by:            o.orders.map { |ord| visit(ord) },
        include_attributes: attributes.flat_map { |p| visit(p) },
        aggregate_by: aggregates.any? ? visit(aggregates.first) : nil,
        upsert_rows: 0,
      )
    end

    def visit_Arel_Nodes_InsertStatement(o)
      raise NotImplementedError, "INSERT ... SELECT" if o.select

      columns = o.columns.map { |c| visit(c) }
      rows    = o.values ? visit(o.values) : [ [] ]

      TurbopufferQuery.new(
        op:        :insert,
        namespace: visit(o.relation),
        filters: nil,
        top_k: nil,
        rank_by: nil,
        include_attributes: nil,
        upsert_rows: rows.map { |row| columns.zip(row).to_h },
      )
    end

    def visit_Arel_Nodes_UpdateStatement(o)
      # columns = o.columns.map { |c| visit(c) }
      rows    = o.values ? visit(o.values) : [ [] ]

      TurbopufferQuery.new(
        op:        :update,
        namespace: visit(o.relation),
        filters:   conjoin(o.wheres.map { |w| visit(w) }),
        top_k: nil,
        rank_by: nil,
        include_attributes: nil,
        upsert_rows: rows # rows.map { |row| columns.zip(row).to_h },
      )
    end

    def visit_Arel_Nodes_DeleteStatement(o)
      TurbopufferQuery.new(
        op:        :delete,
        namespace: visit(o.relation),
        filters:   conjoin(o.wheres.map { |w| visit(w) }),
        top_k: nil,
        rank_by: nil,
        include_attributes: nil,
        upsert_rows: nil
      )
    end

    def visit_ActiveModel_Attribute(o)
      @binds << o

      attribute = @bound_values ? @bound_values[@binds.size - 1] : o

      if ActiveRecord::StatementCache::Substitute === attribute.value_before_type_cast
        return nil if @collecting_binds
        raise "unbound statement-cache placeholder for #{o.name.inspect}"
      end

      attribute.value_for_database
    end
    alias visit_ActiveRecord_Relation_QueryAttribute visit_ActiveModel_Attribute

    def visit_Arel_Nodes_BindParam(o)
      visit(o.value)
    end

    def visit_Arel_Nodes_ValuesList(o)
      o.rows.map { |row| row.map { |v| visit(v) } }
    end

    def visit_Arel_Nodes_JoinSource(o)
      raise NotImplementedError, "turbopuffer has no joins" if o.right.any?
      visit(o.left)
    end

    def visit_Arel_Table(o) = o.name

    # filters
    def visit_Arel_Nodes_And(o)      = [ "And", o.children.map { |c| visit(c) } ]
    def visit_Arel_Nodes_Or(o)       = [ "Or", [ visit(o.left), visit(o.right) ] ]
    def visit_Arel_Nodes_Grouping(o) = visit(o.expr)

    def visit_Arel_Nodes_UnqualifiedColumn(o)
      visit o.expr
    end

    def visit_Arel_Nodes_Assignment(o)
      [ visit(o.left), visit(o.right) ]
    end

    def visit_Arel_Nodes_Equality(o) = [ visit(o.left), "Eq",  visit(o.right) ]
    def visit_Arel_Nodes_NotEqual(o) = [ visit(o.left), "NotEq", visit(o.right) ]
    def visit_Arel_Nodes_GreaterThan(o) = [ visit(o.left), "Gt", visit(o.right) ]
    def visit_Arel_Nodes_GreaterThanOrEqual(o) = [ visit(o.left), "Gte", visit(o.right) ]
    def visit_Arel_Nodes_LessThan(o)    = [ visit(o.left), "Lt", visit(o.right) ]
    def visit_Arel_Nodes_LessThanOrEqual(o)    = [ visit(o.left), "Lte", visit(o.right) ]
    def visit_Arel_Nodes_In(o)          = [ visit(o.left), "In", visit(o.right) ]

    def visit_Arel_Nodes_Count(o)
      [ "COUNT", "id" ]
    end

    # leaves — this is where binds get resolved
    def visit_Arel_Attributes_Attribute(o) = o.name.to_s
    def visit_Arel_Nodes_Casted(o)         = o.value_for_database
    def visit_Arel_Nodes_Quoted(o)         = o.expr
    def visit_Arel_Nodes_Limit(o)          = visit(o.expr)
    def visit_Arel_Nodes_Ascending(o)      = [ visit(o.expr), "asc" ]
    def visit_Arel_Nodes_Descending(o)     = [ visit(o.expr), "desc" ]

    def visit_Arel_Nodes_RankByNode(o)
      [ o.field, o.method, o.arg ]
    end

    def visit_Array(o)   = o.map { |x| visit(x) }
    def visit_Integer(o) = o
    def visit_String(o)  = o
    def visit_NilClass(_) = nil
  end
end
