require "turbopuffer/active_record/version"

module Turbopuffer
  module ActiveRecord
    class Error < StandardError; end

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
