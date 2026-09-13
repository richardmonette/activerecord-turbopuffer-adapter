module Turbopuffer
  module ActiveRecord
    module Type
      class DateTime < ::ActiveRecord::Type::DateTime
        def serialize(value)
          casted = cast(value)

          if casted.respond_to?(:utc)
            casted.utc.iso8601
          elsif casted.is_a?(::Date)
            ::Time.utc(casted.year, casted.month, casted.day).iso8601
          else
            casted
          end
        end
      end
    end
  end
end
