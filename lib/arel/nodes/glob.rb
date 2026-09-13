module Arel::Nodes
  class Glob < Arel::Nodes::Binary
    attr_reader :case_sensitive

    def initialize(left, right, case_sensitive: true)
      super(left, right)
      @case_sensitive = case_sensitive
    end

    def hash = [ self.class, left, right, case_sensitive ].hash

    def eql?(other) = super && case_sensitive == other.case_sensitive
    alias == eql?
  end
end
