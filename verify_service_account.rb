#!/usr/bin/env ruby
# Comprehensive test script to verify service account functionality
# This script tests all the recent changes to ensure they work as intended

require_relative 'lib/mixpanel-ruby'
require 'json'
require 'net/http'

# Color output helpers
def green(text); "\e[32m#{text}\e[0m"; end
def red(text); "\e[31m#{text}\e[0m"; end
def yellow(text); "\e[33m#{text}\e[0m"; end
def blue(text); "\e[34m#{text}\e[0m"; end

# Test counter
$tests_run = 0
$tests_passed = 0
$tests_failed = 0

def test(name)
  $tests_run += 1
  print "Test #{$tests_run}: #{name}... "
  yield
  puts green("✓ PASS")
  $tests_passed += 1
rescue => e
  puts red("✗ FAIL")
  puts red("  Error: #{e.message}")
  puts red("  #{e.backtrace.first(3).join("\n  ")}")
  $tests_failed += 1
end

def assert(condition, message)
  raise message unless condition
end

def assert_equal(expected, actual, message = nil)
  msg = message || "Expected #{expected.inspect}, got #{actual.inspect}"
  raise msg unless expected == actual
end

puts blue("=" * 80)
puts blue("Mixpanel Service Account Verification Script")
puts blue("Testing all recent changes to service account authentication")
puts blue("=" * 80)
puts ""

# ==============================================================================
# SECTION 1: ServiceAccountCredentials class tests
# ==============================================================================

puts yellow("Section 1: ServiceAccountCredentials Class Tests")
puts yellow("-" * 80)

test "Creates credentials with string project_id" do
  creds = Mixpanel::ServiceAccountCredentials.new('user', 'secret', 'project123')
  assert_equal 'user', creds.username
  assert_equal 'secret', creds.secret
  assert_equal 'project123', creds.project_id
end

test "Accepts integer project_id and converts to string" do
  creds = Mixpanel::ServiceAccountCredentials.new('user', 'secret', 12345)
  assert_equal '12345', creds.project_id
  assert creds.project_id.is_a?(String), "project_id should be a String"
end

test "Raises error when username is nil" do
  begin
    Mixpanel::ServiceAccountCredentials.new(nil, 'secret', 'project123')
    raise "Should have raised ArgumentError"
  rescue ArgumentError => e
    assert e.message.include?('username is required'), "Error message should mention username"
  end
end

test "Raises error when secret is nil" do
  begin
    Mixpanel::ServiceAccountCredentials.new('user', nil, 'project123')
    raise "Should have raised ArgumentError"
  rescue ArgumentError => e
    assert e.message.include?('secret is required'), "Error message should mention secret"
  end
end

test "Raises error when project_id is nil" do
  begin
    Mixpanel::ServiceAccountCredentials.new('user', 'secret', nil)
    raise "Should have raised ArgumentError"
  rescue ArgumentError => e
    assert e.message.include?('project_id is required'), "Error message should mention project_id"
  end
end

puts ""

# ==============================================================================
# SECTION 2: JSON Serialization Tests
# ==============================================================================

puts yellow("Section 2: JSON Serialization Tests")
puts yellow("-" * 80)

test "Secret IS included in JSON serialization (for Consumer HTTP Basic Auth)" do
  creds = Mixpanel::ServiceAccountCredentials.new('testuser', 'testsecret', 'proj456')
  json_str = creds.to_json
  parsed = JSON.parse(json_str)

  assert parsed.key?('secret'), "JSON should include 'secret' key"
  assert_equal 'testsecret', parsed['secret']
  assert_equal 'testuser', parsed['username']
  assert_equal 'proj456', parsed['project_id']
end

test "Secret is accessible via attr_reader" do
  creds = Mixpanel::ServiceAccountCredentials.new('user', 'my-secret', 'proj789')
  assert_equal 'my-secret', creds.secret
end

test "Credentials survive JSON round-trip with secret intact" do
  creds = Mixpanel::ServiceAccountCredentials.new('roundtrip', 'secret123', 999)
  message = { 'credentials' => creds }.to_json
  decoded = JSON.parse(message)

  assert decoded['credentials'].key?('secret'), "Secret should be in decoded JSON"
  assert_equal 'secret123', decoded['credentials']['secret']
  assert_equal '999', decoded['credentials']['project_id'], "Integer project_id should be string after round-trip"
end

test "as_json method includes secret" do
  creds = Mixpanel::ServiceAccountCredentials.new('user', 'secret', 'proj')
  hash = creds.as_json

  assert hash.is_a?(Hash), "as_json should return a Hash"
  assert_equal 'secret', hash['secret']
end

puts ""

# ==============================================================================
# SECTION 3: Integration with Tracker and Consumer
# ==============================================================================

puts yellow("Section 3: Integration Tests (Tracker/Consumer Message Format)")
puts yellow("-" * 80)

test "Import message includes credentials in correct format" do
  captured_messages = []

  # Create tracker with custom consumer that captures messages
  tracker = Mixpanel::Tracker.new('test-token') do |type, message|
    captured_messages << [type, message]
  end

  creds = Mixpanel::ServiceAccountCredentials.new('import-user', 'import-secret', 88888)

  tracker.import(
    creds,
    'test-distinct-id',
    'Test Event',
    { 'time' => Time.now.to_i, 'test' => true }
  )

  assert captured_messages.size > 0, "Should have captured at least one message"

  type, message_json = captured_messages.first
  message = JSON.parse(message_json)

  assert_equal 'import', type
  assert message.key?('credentials'), "Message should have 'credentials' key"
  assert_equal 'import-user', message['credentials']['username']
  assert_equal 'import-secret', message['credentials']['secret']
  assert_equal '88888', message['credentials']['project_id']
end

test "Integer project_id flows correctly through import pipeline" do
  captured_messages = []

  tracker = Mixpanel::Tracker.new('test-token') do |type, message|
    captured_messages << [type, message]
  end

  # Pass integer project_id (like from Mixpanel dashboard)
  creds = Mixpanel::ServiceAccountCredentials.new('user', 'secret', 132990)

  tracker.import(
    creds,
    'user-123',
    'Integer Project ID Test',
    { 'time' => Time.now.to_i }
  )

  type, message_json = captured_messages.first
  message = JSON.parse(message_json)

  # Verify it was converted to string
  assert_equal '132990', message['credentials']['project_id']
  assert message['credentials']['project_id'].is_a?(String), "project_id should be String in message"
end

puts ""

# ==============================================================================
# SECTION 4: Edge Cases and Error Handling
# ==============================================================================

puts yellow("Section 4: Edge Cases and Error Handling")
puts yellow("-" * 80)

test "Empty string username raises error" do
  begin
    Mixpanel::ServiceAccountCredentials.new('', 'secret', 'proj')
    raise "Should have raised ArgumentError"
  rescue ArgumentError => e
    assert e.message.include?('username'), "Error should mention username"
  end
end

test "Empty string secret raises error" do
  begin
    Mixpanel::ServiceAccountCredentials.new('user', '', 'proj')
    raise "Should have raised ArgumentError"
  rescue ArgumentError => e
    assert e.message.include?('secret'), "Error should mention secret"
  end
end

test "Empty string project_id raises error" do
  begin
    Mixpanel::ServiceAccountCredentials.new('user', 'secret', '')
    raise "Should have raised ArgumentError"
  rescue ArgumentError => e
    assert e.message.include?('project_id'), "Error should mention project_id"
  end
end

test "Zero as project_id is valid (converts to '0')" do
  creds = Mixpanel::ServiceAccountCredentials.new('user', 'secret', 0)
  assert_equal '0', creds.project_id
end

test "Negative integer project_id is valid (edge case)" do
  creds = Mixpanel::ServiceAccountCredentials.new('user', 'secret', -123)
  assert_equal '-123', creds.project_id
end

test "Very large integer project_id converts correctly" do
  large_id = 9999999999999
  creds = Mixpanel::ServiceAccountCredentials.new('user', 'secret', large_id)
  assert_equal '9999999999999', creds.project_id
end

puts ""

# ==============================================================================
# Print Summary
# ==============================================================================

puts blue("=" * 80)
puts blue("Test Summary")
puts blue("=" * 80)
puts "Total tests run: #{$tests_run}"
puts green("Passed: #{$tests_passed}")
puts red("Failed: #{$tests_failed}") if $tests_failed > 0

puts ""

if $tests_failed == 0
  puts green("✓ All tests passed! Service account functionality is working correctly.")
  puts ""
  puts "Verified functionality:"
  puts "  ✓ ServiceAccountCredentials accepts both string and integer project_id"
  puts "  ✓ Integer project_id is converted to string internally"
  puts "  ✓ Secret IS included in JSON serialization (needed for HTTP Basic Auth)"
  puts "  ✓ All required fields are validated properly"
  puts "  ✓ Credentials flow correctly through import pipeline"
  puts "  ✓ Edge cases handled appropriately"
  exit 0
else
  puts red("✗ Some tests failed. Please review the errors above.")
  exit 1
end
