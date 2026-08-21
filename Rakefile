require "bundler/gem_tasks"
require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/**/*_test.rb"]
end

task :default => :test

# Releasing is disabled while the gem is in development. `rake build` and
# `rake install` still work; only publishing is blocked.
Rake::Task[:release].clear
Rake::Task["release:rubygem_push"].clear
task :release do
  abort "release disabled: this gem is not ready to publish"
end
