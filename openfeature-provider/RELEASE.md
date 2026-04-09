# Releasing the OpenFeature Provider

The OpenFeature provider (`mixpanel-ruby-openfeature`) is published to RubyGems independently from the core SDK.

## Prerequisites

- Ruby 3.1+
- A RubyGems account with permission to push to the `mixpanel-ruby-openfeature` gem
  - For the first upload, you'll need owner access or to create the gem under the Mixpanel org
  - Sign in and get your API key at https://rubygems.org/profile/edit

## Releasing

1. Update the version in `mixpanel-ruby-openfeature.gemspec`

2. Build the gem:
   ```bash
   cd openfeature-provider
   gem build mixpanel-ruby-openfeature.gemspec
   ```

3. Verify the built artifact:
   ```bash
   ls *.gem
   # Should show: mixpanel-ruby-openfeature-<version>.gem
   ```

4. Push to RubyGems:
   ```bash
   gem push mixpanel-ruby-openfeature-<version>.gem
   ```
   You'll be prompted for your RubyGems credentials on first push. Alternatively, configure `~/.gem/credentials` with your API key:
   ```yaml
   ---
   :rubygems_api_key: rubygems_<your-key>
   ```

5. Verify at https://rubygems.org/gems/mixpanel-ruby-openfeature

## Versioning

The OpenFeature provider is versioned independently from the core SDK. The core SDK dependency is declared in the gemspec (`mixpanel-ruby ~> 3.0`) — update it when the provider needs features from a newer core SDK release.
