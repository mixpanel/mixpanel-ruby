#!/usr/bin/env ruby
# Debug version - prints full HTTP request/response

$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), 'lib'))
require 'mixpanel-ruby'
require 'net/http'

# Monkey patch to see HTTP details
module Net
  class HTTPResponse
    alias_method :original_initialize, :initialize
    def initialize(*args)
      original_initialize(*args)
      puts "\n=== HTTP Response ==="
      puts "Code: #{code}"
      puts "Message: #{message}"
      puts "Body: #{body}"
      puts "=" * 50
    end
  end
end

TOKEN = '9c4e9a6caf9f429a7e3821141fc769b7'
USERNAME = 'johnla-admin.5db18a.mp-service-account'
SECRET = 'BzSw3rAjFFifh64EYGT1RVIFgtWL3b7F'
PROJECT_ID = '132990'

puts "Testing Import with Service Account Credentials"
puts "=" * 70
puts ""

credentials = Mixpanel::ServiceAccountCredentials.new(USERNAME, SECRET, PROJECT_ID)

# Create custom error handler
errors = []
error_handler = Mixpanel::ErrorHandler.new do |error|
  errors << error
  puts "\n!!! Error Handler Caught !!!"
  puts "Error class: #{error.class}"
  puts "Error message: #{error.message}"
  if error.respond_to?(:backtrace)
    puts "Backtrace:"
    puts error.backtrace.first(10).join("\n")
  end
end

tracker = Mixpanel::Tracker.new(TOKEN, error_handler)

puts "Sending import request..."
puts "  Username: #{USERNAME}"
puts "  Project ID: #{PROJECT_ID}"
puts ""

result = tracker.import(
  credentials,
  "test-user-#{Time.now.to_i}",
  'Debug Test Event',
  {
    'time' => Time.now.to_i - 3600,
    'test' => true
  }
)

puts ""
puts "Result: #{result.inspect}"

if errors.any?
  puts ""
  puts "CAPTURED ERRORS:"
  errors.each do |error|
    puts "  - #{error.class}: #{error.message}"
  end
end
