module Turbopuffer
  module Rails
    module Schema
      class Attribute
        attr_reader :name, :type, :filterable, :full_text_search, :ann,
                    :notnull, :collation, :auto_increment, :dflt_value

        def initialize(name, type, not_null: 0, filterable: false, full_text_search: false, ann: false)
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
