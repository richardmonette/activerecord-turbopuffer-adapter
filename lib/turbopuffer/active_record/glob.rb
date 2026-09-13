module Turbopuffer
  module ActiveRecord
    class Glob
      attr_reader :pattern, :case_sensitive

      def initialize(pattern, case_sensitive: true)
        @pattern = pattern
        @case_sensitive = case_sensitive
      end
    end
  end
end
