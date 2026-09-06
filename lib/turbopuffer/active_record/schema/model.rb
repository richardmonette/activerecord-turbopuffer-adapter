module Turbopuffer
  module ActiveRecord
    module Schema
      module Model
        extend ActiveSupport::Concern

        DISTANCE_METRICS = [ "cosine_distance", "euclidean_squared" ].freeze

        included do
          class_attribute :turbopuffer_attributes,        instance_accessor: false, default: [].freeze
          class_attribute :_turbopuffer_distance_metric,  instance_accessor: false, default: "cosine_distance"
        end

        class << self
          def namespaces
            ::ActiveRecord::Base.descendants.select do |model|
              model.respond_to?(:turbopuffer_namespace?) &&
                !model.abstract_class? &&
                model.turbopuffer_namespace?
            end
          end

          def for_table(table_name)
            model = namespaces.find { |m| m.table_name == table_name }

            unless model
              raise UnknownNamespace,
                "No turbopuffer namespace registered for #{table_name.inspect}. " \
                "Declare attributes in the model with `turbopuffer_attribute`. " \
                "Registered: #{namespaces.map(&:table_name).sort.join(", ")}"
            end

            model
          end
        end

        class_methods do
          def turbopuffer_attribute(name, type, not_null: 0, filterable: false,
                                    full_text_search: false, ann: false)
            attribute = ::Turbopuffer::ActiveRecord::Schema::Attribute.new(
              name.to_s, type, not_null:, filterable:, full_text_search:, ann:
            )

            self.turbopuffer_attributes =
              (turbopuffer_attributes.reject { |a| a.name == attribute.name } + [ attribute ]).freeze

            attribute
          end

          def turbopuffer_distance_metric(value = nil)
            return _turbopuffer_distance_metric if value.nil?

            unless DISTANCE_METRICS.include?(value)
              raise ArgumentError,
                "distance metric must be one of #{DISTANCE_METRICS.join(", ")}, got #{value.inspect}"
            end

            self._turbopuffer_distance_metric = value
          end

          def rank_by(*expression)
            expression = expression.first if expression.size == 1
            order(::Arel::Nodes::RankByNode.new(expression))
          end

          def turbopuffer_namespace? = turbopuffer_attributes.any?

          def turbopuffer_schema_hash
            turbopuffer_attributes.each_with_object({}) do |attribute, schema|
              attrs = { type: attribute.type }

              attrs[:filterable] = true if attribute.filterable
              attrs[:full_text_search] = true if attribute.full_text_search
              attrs[:ann] = true if attribute.ann

              schema[attribute.name] = attrs
            end
          end
        end
      end
    end
  end
end
