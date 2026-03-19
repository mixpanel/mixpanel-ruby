# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name = 'mixpanel-openfeature'
  spec.version = '0.1.0'
  spec.authors = ['Mixpanel']
  spec.email = 'support@mixpanel.com'
  spec.summary = 'OpenFeature provider for Mixpanel feature flags'
  spec.description = 'An OpenFeature provider that wraps the Mixpanel Ruby SDK feature flags'
  spec.homepage = 'https://mixpanel.com'
  spec.license = 'Apache-2.0'
  spec.required_ruby_version = '>= 3.0.0'

  spec.files = Dir['lib/**/*.rb']
  spec.require_paths = ['lib']

  spec.add_runtime_dependency 'openfeature-sdk', '~> 0.5'
  spec.add_runtime_dependency 'mixpanel-ruby', '~> 3.0'

  spec.add_development_dependency 'rspec', '~> 3.0'
end
