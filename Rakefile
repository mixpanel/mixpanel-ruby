require 'rspec/core/rake_task'
require 'rdoc/task'

RSpec::Core::RakeTask.new(:spec) do |spec|
  spec.pattern = 'spec/**/*_spec.rb'
end

Rake::RDocTask.new do |rd|
  rd.main = "Readme.rdoc"
  rd.rdoc_files.include("Readme.rdoc", "lib/**/*.rb")
end

task :default => :spec
