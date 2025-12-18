require 'mixpanel-ruby'

# Configuration
PROJECT_TOKEN = ""
FLAG_KEY = "sample-flag"
FLAG_FALLBACK_VARIANT = "control"
USER_CONTEXT = { "distinct_id" => "ruby-demo-user" }
API_HOST = "api.mixpanel.com"
SHOULD_POLL_CONTINUOUSLY = true
POLLING_INTERVAL_SECONDS = 15

def main
  local_config = {
    api_host: API_HOST,
    enable_polling: SHOULD_POLL_CONTINUOUSLY,
    polling_interval_in_seconds: POLLING_INTERVAL_SECONDS
  }

  tracker = Mixpanel::Tracker.new(PROJECT_TOKEN, local_flags_config: local_config)

  tracker.local_flags.start_polling_for_definitions

  variant_value = tracker.local_flags.get_variant_value(FLAG_KEY, FLAG_FALLBACK_VARIANT, USER_CONTEXT)
  puts "Variant value: #{variant_value}"

    tracker.local_flags.stop_polling_for_definitions
end

main if __FILE__ == $PROGRAM_NAME
