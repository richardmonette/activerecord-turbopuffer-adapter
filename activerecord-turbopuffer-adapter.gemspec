# frozen_string_literal: true

require_relative "lib/turbopuffer/active_record/version"

Gem::Specification.new do |s|
  s.name = "activerecord-turbopuffer-adapter"
  s.version = Turbopuffer::ActiveRecord::VERSION
  s.summary = "Unofficial Active Record database adapter for turbopuffer"
  s.description = "An unofficial, community-maintained Active Record adapter for turbopuffer: vector and " \
                  "full-text ranking, filters, batch writes and aggregates through the familiar ActiveRecord " \
                  "interface. Not affiliated with turbopuffer."
  s.authors = ["Richard Monette"]
  s.email = "richard.monette@gmail.com"
  s.homepage = "https://github.com/richardmonette/activerecord-turbopuffer-adapter"
  s.license = "MIT"
  s.metadata["allowed_push_host"] = "https://rubygems.org"
  s.metadata["source_code_uri"] = s.homepage
  s.metadata["changelog_uri"] = "#{s.homepage}/blob/main/CHANGELOG.md"
  s.metadata["rubygems_mfa_required"] = true.to_s
  s.required_ruby_version = ">= 3.3.0"

  s.files = Dir[
    "lib/**/*.rb",
    "LICENSE.txt"
  ]
  s.extra_rdoc_files = ["README.md"]

  s.add_dependency "activerecord", "~> 8.1"
  s.add_dependency "base64"
  s.add_dependency "railties", "~> 8.1"
  s.add_dependency "turbopuffer", ">= 2.4", "< 3"
end
