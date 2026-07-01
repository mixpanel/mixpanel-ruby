#!/usr/bin/env ruby
# Simple test for import endpoint with service account credentials

require_relative 'lib/mixpanel-ruby'
require 'json'

puts "Simple Import Test with Service Account Credentials"
puts "=" * 60

# Get credentials from environment or prompt
TOKEN = ENV['MIXPANEL_TOKEN']
USERNAME = ENV['MIXPANEL_SA_USERNAME']
SECRET = ENV['MIXPANEL_SA_SECRET']
PROJECT_ID = ENV['MIXPANEL_SA_PROJECT_ID']

if [TOKEN, USERNAME, SECRET, PROJECT_ID].any?(&:nil?)
  puts "Please provide credentials:"
  puts ""
  puts "export MIXPANEL_TOKEN='your-project-token'"
  puts "export MIXPANEL_SA_USERNAME='your-service-account-username'"
  puts "export MIXPANEL_SA_SECRET='your-service-account-secret'"
  puts "export MIXPANEL_SA_PROJECT_ID='your-project-id'"
  puts ""
  puts "Then run: ruby test_import_simple.rb"
  exit 1
end

puts "Configuration:"
puts "  Token: #{TOKEN[0..10]}..."
puts "  Username: #{USERNAME}"
puts "  Project ID: #{PROJECT_ID}"
puts ""

# Track what gets sent
sent_messages = []
tracker = Mixpanel::Tracker.new(TOKEN) do |type, message|
  sent_messages << [type, JSON.parse(message)]
  puts "→ Captured message:"
  puts "  Type: #{type}"
  puts "  Message: #{JSON.pretty_generate(JSON.parse(message))}"
end

# Create credentials
credentials = Mixpanel::ServiceAccountCredentials.new(USERNAME, SECRET, PROJECT_ID)

# Import an event
puts "Importing test event..."
distinct_id = "test-user-#{Time.now.to_i}"
historical_time = Time.now - 3600  # 1 hour ago

result = tracker.import(
  credentials,
  distinct_id,
  'Test Import Event',
  {
    'test' => true,
    'time' => historical_time.to_i
  }
)

puts ""
puts "Result: #{result ? '✅ Success' : '❌ Failed'}"
puts ""

if sent_messages.any?
  msg = sent_messages.last[1]
  puts "Message structure:"
  puts "  Has credentials: #{!msg['credentials'].nil?}"
  puts "  Has api_key: #{!msg['api_key'].nil?}"
  if msg['credentials']
    puts "  Credentials:"
    puts "    username: #{msg['credentials']['username']}"
    puts "    secret: #{msg['credentials']['secret'][0..5]}..."
    puts "    project_id: #{msg['credentials']['project_id']}"
  end
end

puts ""
puts "Now send to actual Mixpanel API? (y/N)"
response = gets.chomp.downcase

if response == 'y'
  puts "Sending to Mixpanel..."
  # Create a real consumer
  real_tracker = Mixpanel::Tracker.new(TOKEN)
  result = real_tracker.import(
    credentials,
    distinct_id,
    'Test Import Event',
    {
      'test' => true,
      'source' => 'ruby-sdk-service-account-test',
      'time' => historical_time.to_i
    }
  )

  puts result ? "✅ Sent successfully!" : "❌ Failed to send"
else
  puts "Skipped sending to API"
end
