# frozen_string_literal: true

require "turbopuffer"

require "arel/visitors/turbopuffer"
require "turbopuffer/active_record/schema"
require "turbopuffer/active_record/type"

module ActiveRecord
  module ConnectionAdapters
    class CachedQuery < ActiveRecord::StatementCache::Query
      def initialize(ast, visitor)
        @ast, @visitor, @retryable = ast, visitor, true
      end

      def sql_for(binds, connection)
        @visitor.compile(@ast, bound_values: binds).first
      end
    end

    class TurbopufferAdapter < AbstractAdapter
      ADAPTER_NAME = "Turbopuffer"

      class << self
        private

        def initialize_type_map(m)
          m.register_type "string",   Type::String.new
          m.register_type "uuid",     Type::String.new
          m.register_type "int",      Type::Integer.new(limit: 8)
          m.register_type "uint",     ::Turbopuffer::ActiveRecord::Type::UnsignedInteger.new(limit: 8)
          m.register_type "float",    Type::Float.new
          m.register_type "bool",     Type::Boolean.new
          m.register_type "datetime", ::Turbopuffer::ActiveRecord::Type::DateTime.new
          m.register_type(%r{\A\[\].+\z}) do |type|
            ::Turbopuffer::ActiveRecord::Type::Array.new(m.lookup(type.delete_prefix("[]")))
          end
          m.register_type(%r{\A\[\d+\]f(?:16|32)\z}) do |type|
            ::Turbopuffer::ActiveRecord::Type::Vector.new(type[/\d+/].to_i)
          end
        end
      end

      TYPE_MAP = Type::TypeMap.new.tap { |m| initialize_type_map(m) }
      EXTENDED_TYPE_MAPS = Concurrent::Map.new

      def column_definitions(table_name)
        ::Turbopuffer::ActiveRecord::Schema::Model.for_table(table_name).turbopuffer_attributes
      end

      def tables
        ::Turbopuffer::ActiveRecord::Schema::Model.namespaces.map(&:table_name).uniq
      end
      def views = []
      def data_sources = tables
      def table_exists?(name) = tables.include?(name.to_s)
      def data_source_exists?(name) = table_exists?(name)

      def supports_insert_on_duplicate_skip? = true
      def supports_insert_on_duplicate_update? = true

      def supports_savepoints? = false
      def supports_ddl_transactions? = false
      def supports_transaction_isolation? = false
      def supports_lazy_transactions? = false
      def supports_restart_db_transaction? = false
      def supports_advisory_locks? = false

      def begin_db_transaction = nil
      def commit_db_transaction   = nil
      def exec_rollback_db_transaction = nil
      def create_savepoint(name = nil)          = nil
      def exec_rollback_to_savepoint(name = nil) = nil
      def release_savepoint(name = nil)          = nil

      def begin_isolated_db_transaction(isolation)
        raise ActiveRecord::TransactionIsolationError, "Turbopuffer does not support isolation levels"
      end

      def primary_key(table_name)
        "id"
      end

      def default_insert_value(column)
        nil
      end

      def self.quote_column_name(name) = name.to_s

      def view_exists?(name) = false

      def write_query?(sql)
        query = sql.is_a?(Array) ? sql.first : sql
        query.op != :select
      end

      def type_cast(value)
        case value
        when Array
          value
        else
          super
        end
      end

      def new_column_from_field(table_name, field, definitions)
        Column.new(field.name, lookup_cast_type(field.type), nil, nil, field.notnull.to_i == 0)
      end

      def build_insert_sql(insert)
        columns = insert.keys_including_timestamps.to_a
        rows, _binds = insert.values_list

        upsert_rows = rows.map do |row|
          attributes = columns.zip(row).to_h
          attributes["id"] ||= SecureRandom.uuid_v7
          attributes
        end

        Arel::Visitors::TurbopufferQuery.new(
          op:          :insert,
          namespace:   insert.model.table_name,
          upsert_rows: upsert_rows
        )
      end

      def high_precision_current_timestamp
        ::Time.current
      end

      def cacheable_query(klass, arel)
        _discarded, binds = visitor.compile(arel.ast, collecting_binds: true)   # only needed to build the BindMap
        [ CachedQuery.new(arel.ast, visitor), binds ]
      end

      TurbopufferResult = Struct.new(:fields, :rows, :affected_rows, keyword_init: true) do
        def self.affected(count) = new(fields: [], rows: [], affected_rows: count)
      end

      def turbopuffer_insert(namespace, query)
        table_name = query.namespace
        model = ::Turbopuffer::ActiveRecord::Schema::Model.for_table(table_name)

        tpuf_insert_args = {
          upsert_rows: query.upsert_rows,
          schema: model.turbopuffer_schema_hash
        }

        if model.turbopuffer_attributes.any?(&:ann)
          tpuf_insert_args[:distance_metric] = model.turbopuffer_distance_metric
        end

        tpuf_result = namespace.write(tpuf_insert_args)

        fields = column_definitions(table_name).map(&:name)
        rows = query.upsert_rows.map { |r| fields.map { |f| r[f] } }

        TurbopufferResult.new(fields: fields, rows: rows, affected_rows: tpuf_result.rows_affected)
      end

      def turbopuffer_update(namespace, query)
        patch = query.upsert_rows.to_h
        pending = pending_patch_filter(patch)
        filters = query.filters ? [ "And", [ query.filters, pending ] ] : pending

        affected = write_in_batches(
          namespace,
          patch_by_filter: { filters: filters, patch: patch.transform_keys(&:to_sym) },
          patch_by_filter_allow_partial: true
        )

        TurbopufferResult.affected(affected)
      end

      def write_in_batches(namespace, args)
        affected = 0

        loop do
          tpuf_result = namespace.write(args)
          affected += tpuf_result.rows_affected

          break unless tpuf_result.rows_remaining

          if tpuf_result.rows_affected.zero?
            raise ActiveRecord::StatementInvalid, "write made no progress: rows still match #{args.inspect}"
          end
        end

        affected
      end

      def pending_patch_filter(patch)
        conditions = patch.flat_map do |attribute, value|
          if value.nil?
            [ [ attribute, "NotEq", nil ] ]
          else
            [ [ attribute, "NotEq", value ], [ attribute, "Eq", nil ] ]
          end
        end

        [ "Or", conditions ]
      end

      def turbopuffer_delete(namespace, query)
        attribute, operator, value = query.filters

        affected = if query.filters.nil?
          turbopuffer_delete_namespace(namespace)
        elsif attribute == "id" && operator == "Eq"
          namespace.write(deletes: [ value ]).rows_affected
        elsif attribute == "id" && operator == "In"
          namespace.write(deletes: value).rows_affected
        else
          write_in_batches(namespace, delete_by_filter: query.filters, delete_by_filter_allow_partial: true)
        end

        TurbopufferResult.affected(affected)
      end

      def turbopuffer_delete_namespace(namespace)
        count = namespace.query(aggregate_by: { count: [ "Count" ] }).aggregations[:count]
        namespace.delete_all
        count
      rescue Turbopuffer::Errors::NotFoundError
        0
      end

      def consistency_for(query)
        model = ::Turbopuffer::ActiveRecord::Schema::Model.for_table(query.namespace)
        level = query.consistency || model.turbopuffer_consistency || @config[:consistency]
        return if level.nil?

        { level: ::Turbopuffer::ActiveRecord::Schema::Model.validate_consistency(level).to_sym }
      end

      def turbopuffer_aggregate(namespace, query)
        aggregate_alias, aggregate = query.aggregate_by

        tpuf_query_args = {
          aggregate_by: { aggregate_alias => aggregate }
        }

        tpuf_query_args[:filters] = query.filters if query.filters
        consistency = consistency_for(query)
        tpuf_query_args[:consistency] = consistency if consistency

        if query.group_by.present?
          tpuf_query_args[:group_by] = query.group_by
          tpuf_query_args[:top_k] = query.top_k if query.top_k.present?
        end

        result = namespace.query(tpuf_query_args)

        if query.group_by.present?
          fields = query.group_by + [ aggregate_alias ]
          rows = result.aggregation_groups.map(&:to_h).map { |g| fields.map { |f| g[f.to_sym] } }

          TurbopufferResult.new(fields:, rows:, affected_rows: 0)
        else
          count = result.aggregations[aggregate_alias.to_sym]

          TurbopufferResult.new(fields: [ aggregate_alias ], rows: [ [ count ] ], affected_rows: 0)
        end
      rescue Turbopuffer::Errors::NotFoundError
        TurbopufferResult.affected(0)
      end

      def turbopuffer_select(namespace, query)
        fields = if query.include_attributes == [ "*" ]
          column_definitions(query.namespace).map(&:name)
        else
          query.include_attributes
        end

        tpuf_query_args = {
          include_attributes: fields,
          top_k: query.top_k.present? ? query.top_k : 10_000
        }

        tpuf_query_args[:rank_by] = query.rank_by.first if query.rank_by.present?
        tpuf_query_args[:filters] = query.filters if query.filters
        consistency = consistency_for(query)
        tpuf_query_args[:consistency] = consistency if consistency

        tpuf_result = namespace.query(tpuf_query_args)

        rows = tpuf_result.rows.map(&:to_h).map { |r| fields.map { |f| r[f.to_sym] } }

        TurbopufferResult.new(fields:, rows:, affected_rows: 0)
      rescue Turbopuffer::Errors::NotFoundError
        TurbopufferResult.affected(0)
      end

      def perform_query(raw_connection, sql, binds, type_casted_binds, prepare:, notification_payload:, batch:)
        tpuf_query = sql.is_a?(Array) ? sql.first : sql

        namespace_name = [ @config[:namespace_prefix], tpuf_query.namespace ].compact_blank.join("-")
        namespace = raw_connection.namespace(namespace_name)

        result = case tpuf_query.op
        when :insert then turbopuffer_insert(namespace, tpuf_query)
        when :update then turbopuffer_update(namespace, tpuf_query)
        when :delete then turbopuffer_delete(namespace, tpuf_query)
        when :select
          if tpuf_query.aggregate_by
            turbopuffer_aggregate(namespace, tpuf_query)
          else
            turbopuffer_select(namespace, tpuf_query)
          end
        end

        notification_payload[:row_count] = result.rows.size
        result
      end

      def arel_visitor
        Arel::Visitors::Turbopuffer.new
      end

      def cast_result(result)
        if result.fields.empty?
          ActiveRecord::Result.empty(affected_rows: result.affected_rows)
        else
          ActiveRecord::Result.new(result.fields, result.rows, affected_rows: result.affected_rows)
        end
      end

      def prefetch_primary_key?(table_name = nil)
        true
      end

      def next_sequence_value(sequence_name)
        SecureRandom.uuid_v7
      end

      def affected_rows(result)
        result.affected_rows
      end

      def get_full_version
        Turbopuffer::VERSION
      end

      def active?
        connected?
      end

      def connect
        @raw_connection = Turbopuffer::Client.new(
          region: @config[:region],
          api_key: @config[:api_key]
        )
      end

      def disconnect!
        @raw_connection = nil
      end

      def requires_reloading? = false

      private

      def reconnect
        connect
      end
    end
  end
end
