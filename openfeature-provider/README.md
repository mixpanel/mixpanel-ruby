# mixpanel-ruby-openfeature

##### _May 13, 2026_ - [openfeature/v0.1.0](https://github.com/mixpanel/mixpanel-ruby/releases/tag/openfeature/v0.1.0)

[![Gem Version](https://img.shields.io/gem/v/mixpanel-ruby-openfeature.svg)](https://rubygems.org/gems/mixpanel-ruby-openfeature)
[![OpenFeature](https://img.shields.io/badge/OpenFeature-compatible-green)](https://openfeature.dev/)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](https://github.com/mixpanel/mixpanel-ruby/blob/master/LICENSE)

An [OpenFeature](https://openfeature.dev/) provider that wraps Mixpanel's feature flags for use with the OpenFeature Ruby SDK. This allows you to use Mixpanel's feature flagging capabilities through OpenFeature's standardized, vendor-agnostic API.

## Overview

This gem provides a bridge between Mixpanel's native feature flags implementation and the OpenFeature specification. By using this provider, you can:

- Leverage Mixpanel's powerful feature flag and experimentation platform
- Use OpenFeature's standardized API for flag evaluation
- Easily switch between feature flag providers without changing your application code
- Integrate with OpenFeature's ecosystem of tools and frameworks

## Installation

Add these gems to your `Gemfile`:

```ruby
gem 'mixpanel-ruby-openfeature'
gem 'openfeature-sdk'
gem 'mixpanel-ruby'
```

Then run:

```bash
bundle install
```

Or install directly:

```bash
gem install mixpanel-ruby-openfeature
```

## Quick Start

### Local Evaluation (Recommended)

Local evaluation downloads flag definitions and evaluates them locally, providing fast, synchronous flag checks with no per-evaluation network requests.

```ruby
require 'mixpanel-ruby'
require 'mixpanel/openfeature'

# 1. Create the provider with local evaluation
provider = Mixpanel::OpenFeature::Provider.from_local(
  'YOUR_PROJECT_TOKEN',
  { poll_interval: 300 } # poll for updated definitions every 300 seconds
)

# 2. Register the provider with OpenFeature
OpenFeature::SDK.configure do |config|
  config.set_provider(provider)
end

# 3. Get a client and evaluate flags
client = OpenFeature::SDK.build_client

show_new_feature = client.fetch_boolean_value(flag_key: 'new-feature-flag', default_value: false)

if show_new_feature
  puts 'New feature is enabled!'
end
```

### Remote Evaluation

Remote evaluation sends each flag check to Mixpanel's servers, which is useful when you need server-side targeting or cannot download flag definitions locally.

```ruby
require 'mixpanel-ruby'
require 'mixpanel/openfeature'

# 1. Create the provider with remote evaluation
provider = Mixpanel::OpenFeature::Provider.from_remote(
  'YOUR_PROJECT_TOKEN',
  {} # remote config options
)

# 2. Register the provider with OpenFeature
OpenFeature::SDK.configure do |config|
  config.set_provider(provider)
end

# 3. Evaluate flags the same way
client = OpenFeature::SDK.build_client
value = client.fetch_string_value(flag_key: 'button-color-test', default_value: 'blue')
```

### Manual Initialization

If you already have a Mixpanel `Tracker` instance, you can pass its flags provider directly:

```ruby
tracker = Mixpanel::Tracker.new('YOUR_PROJECT_TOKEN', nil, local_flags_config: { poll_interval: 300 })
flags_provider = tracker.local_flags
flags_provider.start_polling_for_definitions!

provider = Mixpanel::OpenFeature::Provider.new(flags_provider)
```

## Usage Examples

### Basic Boolean Flag

```ruby
client = OpenFeature::SDK.build_client

is_feature_enabled = client.fetch_boolean_value(flag_key: 'my-feature', default_value: false)

if is_feature_enabled
  # Show the new feature
end
```

### Mixpanel Flag Types and OpenFeature Evaluation Methods

Mixpanel feature flags support three flag types. Use the corresponding OpenFeature evaluation method based on your flag's variant values:

| Mixpanel Flag Type | Variant Values | OpenFeature Method |
|---|---|---|
| Feature Gate | `true` / `false` | `fetch_boolean_value` |
| Experiment | boolean, string, number, or JSON object | `fetch_boolean_value`, `fetch_string_value`, `fetch_number_value`, or `fetch_object_value` |
| Dynamic Config | JSON object | `fetch_object_value` |

```ruby
client = OpenFeature::SDK.build_client

# Feature Gate - boolean variants
is_feature_on = client.fetch_boolean_value(flag_key: 'new-checkout', default_value: false)

# Experiment with string variants
button_color = client.fetch_string_value(flag_key: 'button-color-test', default_value: 'blue')

# Experiment with number variants
max_items = client.fetch_number_value(flag_key: 'max-items', default_value: 10)

# Dynamic Config - JSON object variants
feature_config = client.fetch_object_value(
  flag_key: 'homepage-layout',
  default_value: { 'layout' => 'grid', 'items_per_row' => 3 }
)
```

### Getting Full Resolution Details

If you need additional metadata about the flag evaluation:

```ruby
client = OpenFeature::SDK.build_client

details = client.fetch_boolean_details(flag_key: 'my-feature', default_value: false)

puts details.value       # The resolved value
puts details.variant     # The variant key from Mixpanel
puts details.reason      # Why this value was returned
puts details.error_code  # Error code if evaluation failed
```

### Passing Evaluation Context

You can pass evaluation context to provide additional properties for flag evaluation:

```ruby
context = OpenFeature::SDK::EvaluationContext.new(
  targeting_key: 'user-123',
  email: 'user@example.com',
  plan: 'premium'
)

value = client.fetch_boolean_value(
  flag_key: 'premium-feature',
  default_value: false,
  evaluation_context: context
)
```

### Accessing the Mixpanel Tracker

When using the `from_local` or `from_remote` class methods, you can access the underlying Mixpanel tracker for tracking events:

```ruby
provider = Mixpanel::OpenFeature::Provider.from_local('YOUR_PROJECT_TOKEN', {})

# Access the tracker for event tracking
provider.mixpanel.track('user-123', 'Page View', { 'page' => '/home' })
```

## Cleanup

When you are done using the provider, shut it down to stop any background polling:

```ruby
provider.shutdown
```

## Error Handling

The provider uses OpenFeature's standard error codes to indicate issues during flag evaluation:

### PROVIDER_NOT_READY

Returned when flags are evaluated before the provider has finished initializing (e.g., before flag definitions have been fetched for local evaluation).

### FLAG_NOT_FOUND

Returned when the requested flag does not exist in Mixpanel.

```ruby
details = client.fetch_boolean_details(flag_key: 'nonexistent-flag', default_value: false)

if details.error_code == OpenFeature::SDK::Provider::ErrorCode::FLAG_NOT_FOUND
  puts 'Flag does not exist, using default value'
end
```

### TYPE_MISMATCH

Returned when the flag value type does not match the requested type.

```ruby
# If 'my-flag' returns a string in Mixpanel but you request a boolean...
details = client.fetch_boolean_details(flag_key: 'my-flag', default_value: false)

if details.error_code == OpenFeature::SDK::Provider::ErrorCode::TYPE_MISMATCH
  puts 'Flag is not a boolean, using default value'
end
```

## FAQ

### What Ruby versions are supported?

Ruby 3.1.0 or later is required.

### What is the difference between local and remote evaluation?

**Local evaluation** downloads all flag definitions upfront and evaluates them in-process. This is faster (no network round-trip per evaluation) and works offline after the initial fetch. Use `from_local` for this mode.

**Remote evaluation** sends each flag check to Mixpanel's servers. This ensures you always have the latest flag values and supports server-side-only targeting rules. Use `from_remote` for this mode.

### Does targetingKey have special meaning?

Unlike some feature flag providers, `targetingKey` is not used as a special bucketing key in Mixpanel. It is passed as another context property alongside all other fields. Mixpanel's server-side configuration determines which properties are used for targeting rules and bucketing.

### Does the provider call mixpanel.identify()?

No. User identity should be managed separately through the Mixpanel tracker's `track` or `people` methods. The provider only handles feature flag evaluation.

### How are exposure events tracked?

When a flag is successfully resolved, the provider automatically reports an exposure event via `report_exposure: true`. This tracks `$experiment_started` events in Mixpanel for analytics and experimentation reporting.

### Can I use this with Rails?

Yes. A common pattern is to initialize the provider in an initializer:

```ruby
# config/initializers/openfeature.rb
provider = Mixpanel::OpenFeature::Provider.from_local(
  ENV['MIXPANEL_TOKEN'],
  { poll_interval: 300 }
)

OpenFeature::SDK.configure do |config|
  config.set_provider(provider)
end

at_exit { provider.shutdown }
```

Then use it in controllers or services:

```ruby
client = OpenFeature::SDK.build_client
show_banner = client.fetch_boolean_value(flag_key: 'show-banner', default_value: false)
```

## License

Apache-2.0
