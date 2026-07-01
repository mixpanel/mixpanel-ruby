#!/usr/bin/env ruby
# Debug import endpoint

require_relative 'lib/mixpanel-ruby'
require 'json'
require 'net/http'

TOKEN = '9c4e9a6caf9f429a7e3821141fc769b7'
USERNAME = 'johnla-admin.5db18a.mp-service-account'
SECRET = 'BzSw3rAjFFifh64EYGT1RVIFgtWL3b7F'
PROJECT_ID = '132990'

puts "Debug Import Endpoint"
puts "=" * 70
puts ""

# Capture HTTP traffic
captured_requests = []

class DebugConsumer < Mixpanel::Consumer
  attr_reader :last_request_info

  def request(endpoint, form_data, credentials = nil, type = nil)
    puts "  Request details:"
    puts "    Endpoint: #{endpoint}"
    puts "    Type: #{type}"
    puts "    Form data keys: #{form_data.keys.join(', ')}"
    puts "    Has credentials: #{!credentials.nil?}"

    if credentials
      puts "    Credentials:"
      puts "      username: #{credentials['username']}"
      puts "      project_id: #{credentials['project_id']}"
    end
    puts ""

    # Call parent to actually make the request
    code, body = super

    puts "  Response:"
    puts "    HTTP Code: #{code}"
    puts "    Body: #{body}"
    puts ""

    [code, body]
  end
end

credentials = Mixpanel::ServiceAccountCredentials.new(USERNAME, SECRET, PROJECT_ID)
consumer = DebugConsumer.new

tracker = Mixpanel::Tracker.new(TOKEN) do |type, message|
  puts "Sink called with type: #{type}"
  parsed = JSON.parse(message)
  puts "Message keys: #{parsed.keys.join(', ')}"
  puts ""

  consumer.send!(type, message)
end

distinct_id = "debug-test-#{Time.now.to_i}"
historical_time = Time.now.to_i - 3600

puts "Calling import..."
puts ""

begin
  result = tracker.import(
    credentials,
    distinct_id,
    'Debug Test Event',
    { 'time' => historical_time, 'test' => true }
  )

  puts "Result: #{result}"
rescue => e
  puts "Error: #{e.class} - #{e.message}"
  puts e.backtrace.first(10).join("\n")
end
