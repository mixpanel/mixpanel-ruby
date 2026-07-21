# Changelog

## openfeature/v0.2.0

- Dispatch on `SelectedVariant#fallback_reason` so `MISSING_CONTEXT_KEY`,
  `NO_ROLLOUT_MATCH`, and `BACKEND_ERROR` map to distinct OpenFeature
  responses instead of every fallback collapsing to `FLAG_NOT_FOUND`.
  Requires `mixpanel-ruby >= 3.3.0`.

## [openfeature/v0.1.0](https://github.com/mixpanel/mixpanel-ruby/tree/openfeature/v0.1.0) (2026-05-13)

Initial release of the Mixpanel OpenFeature provider for Ruby.
