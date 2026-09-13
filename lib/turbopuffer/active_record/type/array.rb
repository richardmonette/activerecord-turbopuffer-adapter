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
          return if value.nil?

          ::Array.wrap(value).map { |element| @element_type.serialize(element) }
        end

        def deserialize(value)
          return if value.nil?

          value.map { |element| @element_type.deserialize(element) }
        end
      end
    end
  end
end
