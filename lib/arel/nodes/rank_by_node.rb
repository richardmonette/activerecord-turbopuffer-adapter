module Arel::Nodes
  class RankByNode < Arel::Nodes::Unary
    attr_reader :field, :method, :arg
    def initialize(field, method, arg)
      @field, @method, @arg = field, method, arg
      super(nil)
    end
  end
end
