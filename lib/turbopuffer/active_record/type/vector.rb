module Turbopuffer
  module ActiveRecord
    module Type
      class Vector < ::ActiveModel::Type::Value
        include ::ActiveModel::Type::Helpers::Mutable

        def initialize(dimensions, integer: false)
          @dimensions = dimensions
          @integer = integer
          super()
        end

        def serialize(value)
          return if value.nil?

          vector = ::Array.wrap(value).map { |component| component(component) }

          unless vector.size == @dimensions
            raise ArgumentError, "expected a vector of #{@dimensions} dimensions, got #{vector.size}"
          end

          vector
        end

        def deserialize(value)
          value
        end

        private

        def component(value)
          number = Float(value)
          return number unless @integer

          unless number == number.to_i
            raise ArgumentError, "expected an integer vector component, got #{value.inspect}"
          end

          number.to_i
        end
      end
    end
  end
end
