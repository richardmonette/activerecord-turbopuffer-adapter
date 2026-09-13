module Turbopuffer
  module ActiveRecord
    module Type
      class UnsignedInteger < ::ActiveRecord::Type::Integer
        private

        def max_value = 1 << 64
        def min_value = 0
      end
    end
  end
end
