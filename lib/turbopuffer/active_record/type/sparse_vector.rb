module Turbopuffer
  module ActiveRecord
    module Type
      class SparseVector < ::ActiveModel::Type::Value
        include ::ActiveModel::Type::Helpers::Mutable

        def serialize(value)
          return if value.nil?

          value.to_h { |key, weight| [ key.to_s, Float(weight) ] }
        end

        def deserialize(value)
          return if value.nil?

          value.to_h.transform_keys(&:to_s)
        end
      end
    end
  end
end
