module Turbopuffer
  module ActiveRecord
    module Schema
      class Attribute
        TYPES = %r{\A(?:\[\])?(?:string|uuid|int|uint|bool|datetime)\z|\A\[\d+\]f(?:16|32)\z}

        attr_reader :name, :type, :filterable, :full_text_search, :ann,
                    :notnull, :collation, :auto_increment, :dflt_value

        def initialize(name, type, not_null: 0, filterable: false, full_text_search: false, ann: false)
          type = type.to_s

          unless TYPES.match?(type)
            raise ArgumentError, "unknown turbopuffer type #{type.inspect} for attribute #{name.inspect}"
          end

          @name = name
          @type = type
          @filterable = filterable
          @full_text_search = full_text_search
          @ann = ann

          @notnull = not_null
          @collation = nil
          @auto_increment = false
          @dflt_value = nil
        end
      end
    end
  end
end
