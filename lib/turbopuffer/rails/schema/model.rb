module Turbopuffer
  module Rails
    module Schema
      module Model
        extend ActiveSupport::Concern

        included do
          class_attribute :turbopuffer_attributes,      instance_accessor: false, default: [].freeze
          class_attribute :turbopuffer_distance_metric, instance_accessor: false, default: nil
        end

        class << self
          def namespaces
            ActiveRecord::Base.descendants.select do |model|
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
                                    full_text_search: false, ann: false, distance_metric: nil)
            attribute = ::Turbopuffer::Rails::Schema::Attribute.new(
              name.to_s, type, not_null:, filterable:, full_text_search:, ann:
            )

            self.turbopuffer_attributes =
              (turbopuffer_attributes.reject { |a| a.name == attribute.name } + [ attribute ]).freeze

            self.turbopuffer_distance_metric = distance_metric if distance_metric

            attribute
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
