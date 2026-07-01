require_relative 'lib/mixpanel-ruby'
require 'json'

TOKEN = '9c4e9a6caf9f429a7e3821141fc769b7'
USERNAME = 'johnla-admin.5db18a.mp-service-account'
SECRET = 'BzSw3rAjFFifh64EYGT1RVIFgtWL3b7F'
PROJECT_ID = '132990'

puts "Testing Service Account Import"
puts "=" * 60

# Capture what gets sent
sent = []
tracker = Mixpanel::Tracker.new(TOKEN) do |type, message|
  sent << [type, JSON.parse(message)]
end

credentials = Mixpanel::ServiceAccountCredentials.new(USERNAME, SECRET, PROJECT_ID)
distinct_id = "test-#{Time.now.to_i}"
historical_time = Time.now.to_i - 3600

puts "Importing event with credentials..."
puts "  Distinct ID: #{distinct_id}"
puts "  Time: #{Time.at(historical_time)}"
puts ""

tracker.import(
  credentials,
  distinct_id,
  'Ruby SDK Service Account Test',
  { 'time' => historical_time, 'test' => true }
)

if sent.any?
  msg = sent.first[1]
  puts "Message structure:"
  puts "  Type: #{sent.first[0]}"
  puts "  Has credentials: #{!msg['credentials'].nil?}"
  puts "  Has api_key: #{!msg['api_key'].nil?}"
  
  if msg['credentials']
    puts ""
    puts "Credentials in message:"
    puts JSON.pretty_generate(msg['credentials'])
  end
end

puts ""
puts "Now testing with real consumer..."

# Test with real consumer
consumer = Mixpanel::Consumer.new
real_tracker = Mixpanel::Tracker.new(TOKEN) do |type, message|
  consumer.send!(type, message)
end

begin
  result = real_tracker.import(
    credentials,
    distinct_id,
    'Ruby SDK Service Account Test',
    { 'time' => historical_time, 'test' => true, 'source' => 'ruby-sdk-verification' }
  )
  
  puts result ? "✅ Import successful!" : "❌ Import failed"
rescue => e
  puts "❌ Error: #{e.class} - #{e.message}"
  puts e.backtrace.first(3).join("\n")
end
