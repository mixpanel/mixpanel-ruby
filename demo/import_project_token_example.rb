#!/usr/bin/env ruby
# Example 02: Import Historical Events — Project Token Auth
#
# Use tracker.import with a project token when you don't have a service account.
# The token is sent as the HTTP Basic Auth username with an empty password.
#
# Run: bundle exec ruby demo/import_project_token_example.rb

$LOAD_PATH.unshift File.join(__dir__, '../../lib')
require 'mixpanel-ruby'

# ── Configuration ─────────────────────────────────────────────────────────────
PROJECT_TOKEN = 'your_project_token'
# ──────────────────────────────────────────────────────────────────────────────

tracker = Mixpanel::Tracker.new(PROJECT_TOKEN)

credentials = { project_token: PROJECT_TOKEN }

puts '--- Import a single historical event ---'
result = tracker.import(credentials, 'user_001', 'Subscription Started', {
  'plan'            => 'Pro',
  'billing_period'  => 'monthly',
  'time'            => Time.parse('2024-03-10 12:00:00 UTC').to_i,
})
puts "Success: #{result}"

puts "\n--- Import with no explicit timestamp (defaults to now) ---"
result = tracker.import(credentials, 'user_002', 'Feature Used', {
  'feature_name' => 'dark_mode',
})
puts "Success: #{result}"

puts "\n--- Import multiple distinct users ---"
users = %w[user_100 user_101 user_102 user_103]
users.each_with_index do |user_id, idx|
  timestamp = (Time.now - (idx * 86_400)).to_i   # each event one day apart
  result = tracker.import(credentials, user_id, 'Daily Active', {
    'day_offset' => idx,
    'time'       => timestamp,
  })
  puts "  #{user_id}: #{result ? 'ok' : 'FAILED'}"
end

puts "\n--- Import with rich properties ---"
result = tracker.import(credentials, 'user_050', 'Order Placed', {
  'order_id'     => 'ORD-9876',
  'items'        => 3,
  'total_usd'    => 124.50,
  'coupon_used'  => true,
  'channel'      => 'email_campaign',
  'campaign_id'  => 'summer_sale_2024',
  'time'         => Time.parse('2024-07-04 18:30:00 UTC').to_i,
})
puts "Success: #{result}"

puts "\nDone."
