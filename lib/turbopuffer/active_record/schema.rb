require "arel/nodes/glob"
require "arel/nodes/rank_by_node"
require "turbopuffer/active_record/glob"
require "turbopuffer/active_record/schema/attribute"
require "turbopuffer/active_record/schema/model"

module Turbopuffer
  module ActiveRecord
    module Schema
      class UnknownNamespace < StandardError; end
    end
  end
end
