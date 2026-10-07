require "turbopuffer/active_record/version"

module Turbopuffer
  module ActiveRecord
    class Error < StandardError; end

    NAMESPACE_ANNOTATION = "turbopuffer_namespace="

    def self.namespace_override
      ActiveSupport::IsolatedExecutionState[:turbopuffer_namespace]
    end

    def self.with_namespace(name)
      previous = namespace_override
      ActiveSupport::IsolatedExecutionState[:turbopuffer_namespace] = name
      yield
    ensure
      ActiveSupport::IsolatedExecutionState[:turbopuffer_namespace] = previous
    end

    # Teaches Active Record that `adapter: turbopuffer` in database.yml maps to
    # our adapter. The railtie calls this during boot; test harnesses and
    # non-Rails consumers call it themselves.
    def self.register_adapter!
      ::ActiveRecord::ConnectionAdapters.register(
        "turbopuffer",
        "ActiveRecord::ConnectionAdapters::TurbopufferAdapter",
        "active_record/connection_adapters/turbopuffer_adapter"
      )
    end
  end
end

require "turbopuffer/active_record/railtie" if defined?(::Rails::Railtie)
