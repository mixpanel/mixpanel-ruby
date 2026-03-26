#!/usr/bin/env ruby
# Example 01: Import Historical Events — Service Account Auth
#
# Use tracker.import with a service account when you need to backfill historical
# events. The SDK authenticates via HTTP Basic Auth and passes the project_id as
# a query parameter to the /import endpoint.
#
# Run: bundle exec ruby demo/import_service_account_example.rb

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'mixpanel-ruby'

# ── Configuration ─────────────────────────────────────────────────────────────
PROJECT_TOKEN               = 'your_token_here'
SERVICE_ACCOUNT_USERNAME    = 'sa-user'   # e.g. sa-abc123@serviceaccount.mixpanel.com
SERVICE_ACCOUNT_PASSWORD    = 'sa-password'
PROJECT_ID                  = 'your_p_id'                 # numeric project ID as a string
# ──────────────────────────────────────────────────────────────────────────────

tracker = Mixpanel::Tracker.new(PROJECT_TOKEN)

credentials = {
  service_account_username: SERVICE_ACCOUNT_USERNAME,
  service_account_password: SERVICE_ACCOUNT_PASSWORD,
  project_id:               PROJECT_ID,
}

puts '--- Import a single historical event ---'
result = tracker.import(credentials, 'user_001', 'Purchase Completed', {
  'product_name' => 'Vintage Widget',
  'price'        => 49.99,
  'time'         => Time.parse('2024-01-15 10:30:00 UTC').to_i,
})
puts "Success: #{result}"

puts "\n--- Import with a very old timestamp ---"
result = tracker.import(credentials, 'user_002', 'Account Created', {
  'plan'   => 'Free',
  'source' => 'organic',
  'time'   => Time.parse('2020-06-01 08:00:00 UTC').to_i,
})
puts "Success: #{result}"

puts "\n--- Import with IP for geolocation ---"
result = tracker.import(
  credentials,
  'user_003',
  'App Installed',
  { 'platform' => 'iOS', 'time' => Time.parse('2023-03-20 14:45:00 UTC').to_i },
  '203.0.113.10'   # ip
)
puts "Success: #{result}"

puts "\n--- Batch import: multiple events in a loop ---"
events = [
  { user: 'user_010', event: 'Video Started',  ts: '2024-02-01 09:00:00 UTC', props: { 'video_id' => 'v_001' } },
  { user: 'user_010', event: 'Video Paused',   ts: '2024-02-01 09:04:32 UTC', props: { 'video_id' => 'v_001', 'position_sec' => 272 } },
  { user: 'user_010', event: 'Video Finished', ts: '2024-02-01 09:18:10 UTC', props: { 'video_id' => 'v_001' } },
]

events.each do |e|
  result = tracker.import(credentials, e[:user], e[:event], e[:props].merge('time' => Time.parse(e[:ts]).to_i))
  puts "  Import '#{e[:event]}': #{result ? 'ok' : 'FAILED'}"
end

puts "\nDone."
