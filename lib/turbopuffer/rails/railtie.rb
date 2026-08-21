require "rails/railtie"

module Turbopuffer
  module Rails
    class Railtie < ::Rails::Railtie
      initializer "turbopuffer.register_adapter", before: "active_record.initialize_database" do
        ::Turbopuffer::Rails.register_adapter!
      end

      initializer "turbopuffer.model_extensions" do
        ActiveSupport.on_load(:active_record) do
          require "turbopuffer/rails/schema"

          include ::Turbopuffer::Rails::Schema::Model
        end
      end
    end
  end
end
