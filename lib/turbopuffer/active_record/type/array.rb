module Turbopuffer
  module ActiveRecord
    module Type
      class Array < ::ActiveModel::Type::Value
        include ::ActiveModel::Type::Helpers::Mutable

        def initialize(element_type)
          @element_type = element_type
          super()
        end

        def serialize(value)
          case value
          when nil then nil
          when ::Array then value.map { |element| @element_type.serialize(element) }
          else @element_type.serialize(value)
          end
        end

        def deserialize(value)
          case value
          when nil then nil
          when ::Array then value.map { |element| @element_type.deserialize(element) }
          else @element_type.deserialize(value)
          end
        end
      end
    end
  end
end
