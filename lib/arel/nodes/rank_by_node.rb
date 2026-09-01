module Arel::Nodes
  class RankByNode < Arel::Nodes::Unary
    attr_reader :expression

    def initialize(*expression)
      @expression = expression.size == 1 ? expression.first : expression
      super(nil)
    end

    def hash = [ self.class, expression ].hash

    def eql?(other) = self.class == other.class && expression == other.expression
    alias == eql?
  end
end
