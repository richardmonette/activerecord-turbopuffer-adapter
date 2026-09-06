# frozen_string_literal: true

require_relative "lib/turbopuffer/active_record/version"

Gem::Specification.new do |s|
  s.name = "activerecord-turbopuffer-adapter"
  s.version = Turbopuffer::ActiveRecord::VERSION
  s.summary = "Active Record adapter for turbopuffer"
  s.description = "Interact with turbopuffer through a native feeling Active Record database adapter"
  s.authors = ["Richard Monette"]
  s.email = "richard.monette@gmail.com"
  s.homepage = "https://github.com/richardmonette/activerecord-turbopuffer-adapter"
  s.license = "MIT"
  # Not ready to publish: point pushes at a host that does not exist so an
  # accidental `gem push` is refused. Set to https://rubygems.org to release.
  s.metadata["allowed_push_host"] = "https://rubygems.invalid"
  s.metadata["homepage_uri"] = s.homepage
  s.metadata["source_code_uri"] = s.homepage
  s.metadata["rubygems_mfa_required"] = true.to_s
  s.required_ruby_version = ">= 3.3.0"

  s.files = Dir[
    "lib/**/*.rb",
    "LICENSE.txt"
  ]
  s.extra_rdoc_files = ["README.md"]

  s.add_dependency "activerecord", "~> 8.1"
  s.add_dependency "railties", "~> 8.1"
  s.add_dependency "turbopuffer", ">= 2.4", "< 3"
end
