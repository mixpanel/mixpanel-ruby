# Changelog

## [Unreleased]

### Added

- Service account authentication support via `ServiceAccountCredentials` class
- `Tracker.new()`, `Events.new()`, `Consumer.new()`, and `BufferedConsumer.new()` now accept `credentials:` parameter
- Credentials are passed to feature flags providers (local and remote) for authenticated API access
- Authentication validation: `import()` now raises `ArgumentError` when called without either `api_key` or `credentials`
- Comprehensive test coverage for credential handling and security in `spec/mixpanel-ruby/credentials_spec.rb` and `spec/mixpanel-ruby/credentials_security_spec.rb`

### Changed

- When using service account credentials, pass `nil` as the first parameter to `import()`: `tracker.import(nil, distinct_id, event, properties)` instead of passing an API key
- Credentials are stored as instance variables and used only for HTTP Basic Auth headers, never serialized to JSON payloads

## [v3.1.0](https://github.com/mixpanel/mixpanel-ruby/tree/v3.1.0) (2026-05-13)

Initial entry for the standardized release process. See `Readme.rdoc` for prior version history.
