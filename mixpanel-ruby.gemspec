spec = Gem::Specification.new do |spec|
  spec.name = 'mixpanel-ruby'
  spec.version = '1.0.0'
  spec.require_paths = ['lib']
  spec.summary = 'Official Mixpanel tracking library for ruby'
  spec.description = 'The official Mixpanel tracking library for ruby'
  spec.authors = [ 'Mixpanel' ]
  spec.email = 'support@mixpanel.com'
  spec.homepage = 'https://mixpanel.com/help/reference/ruby'

  spec.add_development_dependency('rake')
  spec.add_development_dependency('rspec')
  spec.add_development_dependency('webmock')
end
