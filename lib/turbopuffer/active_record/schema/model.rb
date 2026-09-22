module Turbopuffer
  module ActiveRecord
    module Schema
      module Model
        extend ActiveSupport::Concern

        DISTANCE_METRICS = [ "cosine_distance", "euclidean_squared" ].freeze
        CONSISTENCY_LEVELS = [ "strong", "eventual" ].freeze

        included do
          class_attribute :turbopuffer_attributes,        instance_accessor: false, default: [].freeze
          class_attribute :_turbopuffer_distance_metric,  instance_accessor: false, default: "cosine_distance"
          class_attribute :_turbopuffer_consistency,      instance_accessor: false, default: nil
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

          def validate_consistency(level)
            level = level.to_s

            unless CONSISTENCY_LEVELS.include?(level)
              raise ArgumentError,
                "consistency must be one of #{CONSISTENCY_LEVELS.join(", ")}, got #{level.inspect}"
            end

            level
          end
        end

        class_methods do
          def turbopuffer_attribute(name, type, not_null: 0, filterable: false,
                                    full_text_search: false, ann: false, glob: false, regex: false)
            attribute = ::Turbopuffer::ActiveRecord::Schema::Attribute.new(
              name.to_s, type, not_null:, filterable:, full_text_search:, ann:, glob:, regex:
            )

            self.turbopuffer_attributes =
              (turbopuffer_attributes.reject { |a| a.name == attribute.name } + [ attribute ]).freeze

            attribute
          end

          def turbopuffer_distance_metric(value = nil)
            return _turbopuffer_distance_metric if value.nil?

            value = value.to_s

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

          def glob(pattern, case_sensitive: true)
            ::Turbopuffer::ActiveRecord::Glob.new(pattern, case_sensitive:)
          end

          def consistency(level)
            optimizer_hints("consistency=#{Model.validate_consistency(level)}")
          end

          def turbopuffer_consistency(value = nil)
            return _turbopuffer_consistency if value.nil?

            self._turbopuffer_consistency = Model.validate_consistency(value)
          end

          def predicate_builder
            @predicate_builder ||= super.tap do |builder|
              builder.register_handler(::Regexp, lambda { |attribute, regexp|
                ::Arel::Nodes::Regexp.new(attribute, ::Arel::Nodes.build_quoted(regexp.source), !regexp.casefold?)
              })

              builder.register_handler(::Turbopuffer::ActiveRecord::Glob, lambda { |attribute, glob|
                ::Arel::Nodes::Glob.new(attribute, ::Arel::Nodes.build_quoted(glob.pattern), case_sensitive: glob.case_sensitive)
              })
            end
          end

          def turbopuffer_namespace? = turbopuffer_attributes.any?

          def turbopuffer_schema_hash
            turbopuffer_attributes.each_with_object({}) do |attribute, schema|
              attrs = { type: attribute.type }

              attrs[:filterable] = true if attribute.filterable
              attrs[:full_text_search] = true if attribute.full_text_search
              attrs[:ann] = true if attribute.ann
              attrs[:glob] = true if attribute.glob
              attrs[:regex] = true if attribute.regex

              schema[attribute.name] = attrs
            end
          end
        end
      end
    end
  end
end
