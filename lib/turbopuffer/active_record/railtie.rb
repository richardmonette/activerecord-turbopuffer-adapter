require "rails/railtie"

module Turbopuffer
  module ActiveRecord
    class Railtie < ::Rails::Railtie
      initializer "turbopuffer.register_adapter", before: "active_record.initialize_database" do
        ::Turbopuffer::ActiveRecord.register_adapter!
      end

      initializer "turbopuffer.model_extensions" do
        ActiveSupport.on_load(:active_record) do
          require "turbopuffer/active_record/schema"

          include ::Turbopuffer::ActiveRecord::Schema::Model
        end
      end
    end
  end
end
