require "base64"

module Turbopuffer
  module ActiveRecord
    module Type
      class Bytes < ::ActiveModel::Type::Value
        def serialize(value)
          return if value.nil?

          Base64.strict_encode64(value)
        end

        def deserialize(value)
          return if value.nil?

          Base64.decode64(value)
        end
      end
    end
  end
end
