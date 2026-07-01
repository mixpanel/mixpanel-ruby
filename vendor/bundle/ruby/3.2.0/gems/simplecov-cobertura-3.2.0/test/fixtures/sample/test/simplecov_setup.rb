$LOAD_PATH.unshift(File.join(ENV.fetch('GEM_ROOT'), 'lib'))

require 'simplecov'
require 'simplecov-cobertura'

SimpleCov.command_name ENV.fetch('COMMAND_NAME', 'Unit Tests')
SimpleCov.start do
  enable_coverage :branch
  use_merging true
  merge_timeout 3600 # generous so slow CI can't expire run A's result
  root ENV.fetch('PROJECT_ROOT')
  coverage_dir 'coverage'
  formatter SimpleCov::Formatter::CoberturaFormatter
end

require File.join(ENV.fetch('PROJECT_ROOT'), 'lib', 'sample')
require 'test/unit'
