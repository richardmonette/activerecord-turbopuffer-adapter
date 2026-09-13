module Turbopuffer
  module ActiveRecord
    module Type
      class Vector < ::ActiveModel::Type::Value
        include ::ActiveModel::Type::Helpers::Mutable

        def initialize(dimensions)
          @dimensions = dimensions
          super()
        end

        def serialize(value)
          return if value.nil?

          vector = ::Array.wrap(value).map { |component| Float(component) }

          unless vector.size == @dimensions
            raise ArgumentError, "expected a vector of #{@dimensions} dimensions, got #{vector.size}"
          end

          vector
        end

        def deserialize(value)
          value
        end
      end
    end
  end
end
