# frozen_string_literal: true

require "turbopuffer"

require "arel/visitors/turbopuffer"
require "arel/nodes/rank_by_node"

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

      class DateTimeType < ActiveRecord::Type::DateTime
        def serialize(value)
          value.iso8601
        end
      end

      class << self
        private
        def initialize_type_map(m)
          super
          register_class_with_limit(m, "datetime", DateTimeType)
        end
      end

      TYPE_MAP = Type::TypeMap.new.tap { |m| initialize_type_map(m) }
      EXTENDED_TYPE_MAPS = Concurrent::Map.new

      def column_definitions(table_name)
        ::Turbopuffer::Rails::Schema::Model.for_table(table_name).turbopuffer_attributes
      end

      def tables
        ::Turbopuffer::Rails::Schema::Model.namespaces.map(&:table_name).uniq
      end
      def views = []
      def data_sources = tables
      def table_exists?(name) = tables.include?(name.to_s)
      def data_source_exists?(name) = table_exists?(name)

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
        :id
      end

      def self.quote_column_name(name) = name.to_s

      def data_source_sql(name = nil, type: nil)
        "stubbed data_source_sql"
      end

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
        default = field.dflt_value

        type_metadata = nil # fetch_type_metadata(field["type"])
        default_value = nil # extract_value_from_default(default)
        generated_type = nil # extract_generated_type(field)

          # if generated_type.present?
          default_function = default
        # else
        #   default_function = extract_default_function(default_value, default)
        # end

        rowid = false # is_column_the_rowid?(field, definitions)

        Column.new(
          field.name,
          lookup_cast_type(field.type),
          default_value,
          type_metadata,
          field.notnull.to_i == 0,
          default_function,
          collation: field.collation,
          auto_increment: field.auto_increment,
          rowid: rowid,
          generated_type: generated_type
        )
      end

      def cacheable_query(klass, arel)
        _discarded, binds = visitor.compile(arel.ast, collecting_binds: true)   # only needed to build the BindMap
        [ CachedQuery.new(arel.ast, visitor), binds ]
      end

      TurbopufferResult = Struct.new(:fields, :rows, :affected_rows, keyword_init: true)

      def turbopuffer_insert(namespace, query)
        table_name = query.namespace
        model = ::Turbopuffer::Rails::Schema::Model.for_table(table_name)

        tpuf_insert_args = {
          upsert_rows: query.upsert_rows,
          schema: model.turbopuffer_schema_hash
        }

        tpuf_insert_args[:distance_metric] = model.turbopuffer_distance_metric

        tpuf_result = namespace.write(tpuf_insert_args)

        fields = column_definitions(table_name).map(&:name)
        rows = query.upsert_rows.map { |r| fields.map { |f| r[f] } }

        TurbopufferResult.new(fields: fields, rows: rows, affected_rows: tpuf_result.rows_affected)
      end

      def turbopuffer_update(namespace, query)
        tpuf_query_args = {
          patch_by_filter: {
            filters: query.filters.first,
            patch: query.upsert_rows.to_h.transform_keys(&:to_sym)
          }
        }

        tpuf_result = namespace.write(
          tpuf_query_args
        )

        TurbopufferResult.new(fields: [], rows: [], affected_rows: tpuf_result.rows_affected)
      end

      def turbopuffer_delete(namespace, query)
        if query.filters.first[0] == "id"
          # special case for deleting specific id
          tpuf_result = namespace.write(
            deletes: [
              query.filters.first[2]
            ]
          )

          TurbopufferResult.new(fields: [], rows: [], affected_rows: tpuf_result.rows_affected)
        else
          tpuf_result = namespace.write(
            delete_by_filter: query.filters.first
          )

          TurbopufferResult.new(fields: [], rows: [], affected_rows: tpuf_result.rows_affected)
        end
      end

      def turbopuffer_aggregate(namespace, query)
        aggregate_alias, aggregate = query.aggregate_by

        tpuf_query_args = {
          aggregate_by: { aggregate_alias => aggregate }
        }

        tpuf_query_args[:filters] = query.filters.first if query.filters.present?
        tpuf_query_args[:group_by] = query.group_by if query.group_by.present?

        result = namespace.query(tpuf_query_args)

        if query.group_by.present?
          fields = query.group_by + [ aggregate_alias ]
          rows = result.aggregation_groups.map(&:to_h).map { |g| fields.map { |f| g[f.to_sym] } }

          TurbopufferResult.new(fields:, rows:, affected_rows: 0)
        else
          count = result.aggregations[aggregate_alias.to_sym]

          TurbopufferResult.new(fields: [ aggregate_alias ], rows: [ [ count ] ], affected_rows: 0)
        end
      end

      def turbopuffer_select(namespace, query)
        fields = if query.include_attributes == [ "*" ]
          column_definitions(query.namespace).map(&:name)
        else
          query.include_attributes
        end

        begin
          tpuf_query_args = {
            include_attributes: fields
          }

          tpuf_query_args[:top_k] = query.top_k.present? ? query.top_k : 10_000
          tpuf_query_args[:rank_by] = query.rank_by.first if query.rank_by.present?
          tpuf_query_args[:filters] = query.filters.first if query.filters.present?

          tpuf_result = namespace.query(
            tpuf_query_args
          )

          rows = tpuf_result.rows.map(&:to_h).map { |r| fields.map { |f| r[f.to_sym] } }

          TurbopufferResult.new(fields:, rows:, affected_rows: 0)
        rescue Turbopuffer::Errors::NotFoundError
          TurbopufferResult.new(fields: [], rows: [], affected_rows: 0)
        end
      end

      def perform_query(raw_connection, sql, binds, type_casted_binds, prepare:, notification_payload:, batch:)
        tpuf_query = sql.is_a?(Array) ? sql.first : sql

        namespace_name = @config[:namespace_prefix].present? ? "#{@config[:namespace_prefix]}-#{tpuf_query.namespace}" : tpuf_query.namespace
        namespace = raw_connection.namespace(namespace_name)

        result = if tpuf_query.op == :insert
          turbopuffer_insert(namespace, tpuf_query)
        elsif tpuf_query.op == :update
          turbopuffer_update(namespace, tpuf_query)
        elsif tpuf_query.op == :delete
          turbopuffer_delete(namespace, tpuf_query)
        elsif tpuf_query.op == :select && tpuf_query.aggregate_by
          turbopuffer_aggregate(namespace, tpuf_query)
        elsif tpuf_query.op == :select
          turbopuffer_select(namespace, tpuf_query)
        else
          TurbopufferResult.new(fields: [], rows: [], affected_rows: 0)
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
