# frozen_string_literal: true

require File.join(File.dirname(__FILE__), 'lib/mixpanel/openfeature/version.rb')

Gem::Specification.new do |spec|
  spec.name = 'mixpanel-ruby-openfeature'
  spec.version = Mixpanel::OpenFeature::VERSION
  spec.authors = ['Mixpanel']
  spec.email = 'support@mixpanel.com'
  spec.summary = 'OpenFeature provider for Mixpanel feature flags'
  spec.description = 'An OpenFeature provider that wraps the Mixpanel Ruby SDK feature flags'
  spec.homepage = 'https://mixpanel.com'
  spec.license = 'Apache-2.0'
  spec.required_ruby_version = '>= 3.1.0'

  spec.files = Dir['lib/**/*.rb']
  spec.require_paths = ['lib']

  spec.add_runtime_dependency 'openfeature-sdk', '~> 0.5'
  # SDK-126: pinned to `~> 3.3` because the wrapper's provider.rb calls
  # `SelectedVariant#fallback_reason`, which was introduced in the
  # SDK-79 merge and will ship in the next mixpanel-ruby release
  # (3.3.0). Any earlier 3.x release lacks that method and would raise
  # NoMethodError on every evaluation. Do NOT loosen this constraint
  # unless the mixpanel-ruby version being permitted also exposes
  # fallback_reason.
  spec.add_runtime_dependency 'mixpanel-ruby', '~> 3.3'

  spec.add_development_dependency 'rspec', '~> 3.0'
  spec.add_development_dependency 'simplecov'
  spec.add_development_dependency 'simplecov-cobertura'
end
