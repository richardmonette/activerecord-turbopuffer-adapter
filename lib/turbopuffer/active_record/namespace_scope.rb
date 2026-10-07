module Turbopuffer
  module ActiveRecord
    module NamespaceScope
      def turbopuffer_namespace
        annotation = annotate_values.reverse.find { |value| value.start_with?(NAMESPACE_ANNOTATION) }
        annotation&.delete_prefix(NAMESPACE_ANNOTATION)
      end

      def exec_queries(...) = ::Turbopuffer::ActiveRecord.with_namespace(turbopuffer_namespace) { super }
      def insert_all(...)   = ::Turbopuffer::ActiveRecord.with_namespace(turbopuffer_namespace) { super }
      def insert_all!(...)  = ::Turbopuffer::ActiveRecord.with_namespace(turbopuffer_namespace) { super }
      def upsert_all(...)   = ::Turbopuffer::ActiveRecord.with_namespace(turbopuffer_namespace) { super }
    end
  end
end
