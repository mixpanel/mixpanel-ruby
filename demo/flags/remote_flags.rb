require 'mixpanel-ruby'

# Configuration
PROJECT_TOKEN = ""
FLAG_KEY = "sample-flag"
FLAG_FALLBACK_VARIANT = "control"
USER_CONTEXT = { "distinct_id" => "ruby-demo-user" }
API_HOST = "api.mixpanel.com"

remote_config = {
  api_host: API_HOST
}

tracker = Mixpanel::Tracker.new(PROJECT_TOKEN, remote_flags_config: remote_config)

variant_value = tracker.remote_flags.get_variant_value(FLAG_KEY, FLAG_FALLBACK_VARIANT, USER_CONTEXT)
puts "Variant value: #{variant_value}"

