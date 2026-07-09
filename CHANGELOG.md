# Changelog

## [Unreleased]

### Changed

- `Tracker.new()` now accepts `credentials:` parameter for service account authentication
- `Consumer.new()` and `BufferedConsumer.new()` now accept `credentials:` parameter
- `Tracker.new()` now accepts `consumer:` parameter to provide a custom consumer instance
- When using service account credentials, pass `nil` as the first parameter to `import()`: `tracker.import(nil, distinct_id, event, ...)` instead of passing credentials

### Added

- New secure API pattern: credentials passed to constructor are stored as instance variables and used only for HTTP Basic Auth headers, never serialized to JSON
- Warning when both `consumer` and `credentials` parameters are provided to `Tracker.new()` (credentials are ignored in this case - pass them to the consumer instead)
- Comprehensive test coverage for secure credential handling in `spec/mixpanel-ruby/credentials_security_spec.rb`

### Fixed

- `BufferedConsumer` now properly preserves `api_key` when flushing batched messages (previously it was dropped during flush)

## [v3.1.0](https://github.com/mixpanel/mixpanel-ruby/tree/v3.1.0) (2026-05-13)

Initial entry for the standardized release process. See `Readme.rdoc` for prior version history.
