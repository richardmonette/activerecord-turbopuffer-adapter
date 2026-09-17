module Turbopuffer
  module ActiveRecord
    module Schema
      class Attribute
        TYPES = %r{\A(?:\[\])?(?:string|uuid|int|uint|float|bool|datetime)\z|\A\[\d+\]f(?:16|32)\z}

        attr_reader :name, :type, :filterable, :full_text_search, :ann, :glob, :regex, :notnull

        def initialize(name, type, not_null: 0, filterable: false, full_text_search: false,
                       ann: false, glob: false, regex: false)
          type = type.to_s

          unless TYPES.match?(type)
            raise ArgumentError, "unknown turbopuffer type #{type.inspect} for attribute #{name.inspect}"
          end

          @name = name
          @type = type
          @filterable = filterable
          @full_text_search = full_text_search
          @ann = ann
          @glob = glob
          @regex = regex

          @notnull = not_null
        end
      end
    end
  end
end
