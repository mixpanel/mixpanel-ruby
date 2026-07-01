#!/usr/bin/env ruby
# Test script for service account authentication with import and flags

$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), 'lib'))
require 'mixpanel-ruby'

# ==============================================================================
# CONFIGURATION - Replace these with your actual credentials
# ==============================================================================

TOKEN = ENV['MIXPANEL_TOKEN'] || '9c4e9a6caf9f429a7e3821141fc769b7'
SERVICE_ACCOUNT_USERNAME = ENV['MIXPANEL_SA_USERNAME'] || 'johnla-admin.5db18a.mp-service-account'
SERVICE_ACCOUNT_SECRET = ENV['MIXPANEL_SA_SECRET'] || 'BzSw3rAjFFifh64EYGT1RVIFgtWL3b7F'
SERVICE_ACCOUNT_PROJECT_ID = ENV['MIXPANEL_SA_PROJECT_ID'] || '132990'

# Test user distinct_id
DISTINCT_ID = "test-user-#{Time.now.to_i}"

puts "=" * 80
puts "Mixpanel Service Account Authentication Test"
puts "=" * 80
puts ""

# ==============================================================================
# Test 1: Import endpoint with service account credentials
# ==============================================================================

puts "TEST 1: Import Endpoint with Service Account Credentials"
puts "-" * 80

begin
  # Create service account credentials
  credentials = Mixpanel::ServiceAccountCredentials.new(
    SERVICE_ACCOUNT_USERNAME,
    SERVICE_ACCOUNT_SECRET,
    SERVICE_ACCOUNT_PROJECT_ID
  )

  # Create custom error handler class to capture errors
  errors = []
  error_handler = Class.new(Mixpanel::ErrorHandler) do
    define_method(:initialize) do |error_array|
      @errors = error_array
    end

    define_method(:handle) do |error|
      @errors << error
      puts "  ⚠️  Error caught: #{error.class} - #{error.message}"
    end
  end.new(errors)

  # Create tracker with error handler
  tracker = Mixpanel::Tracker.new(TOKEN, error_handler)

  # Import an event (historical event)
  historical_time = Time.now - 86400  # 1 day ago
  result = tracker.import(
    credentials,
    DISTINCT_ID,
    'Service Account Test Event',
    {
      'test_type' => 'import',
      'time' => historical_time.to_i,
      'source' => 'ruby-sdk-test'
    }
  )

  # Give it a moment to process
  sleep 0.1

  if result
    puts "✅ Import successful!"
    puts "   Event: Service Account Test Event"
    puts "   Distinct ID: #{DISTINCT_ID}"
    puts "   Time: #{historical_time}"
  else
    puts "❌ Import failed (returned false)"
  end

  # Always check for errors
  if errors.any?
    puts ""
    puts "❌ ERRORS CAPTURED:"
    errors.each_with_index do |error, i|
      puts "  Error #{i+1}:"
      puts "    Class: #{error.class}"
      puts "    Message: #{error.message}"
      puts ""
    end
  end
rescue => e
  puts "❌ Import error: #{e.class} - #{e.message}"
  puts "   #{e.backtrace.first(10).join("\n   ")}"
end

puts ""

# ==============================================================================
# Test 2: Feature Flags with service account credentials
# ==============================================================================

puts "TEST 2: Feature Flags with Service Account Credentials"
puts "-" * 80

begin
  # Create service account credentials
  credentials = Mixpanel::ServiceAccountCredentials.new(
    SERVICE_ACCOUNT_USERNAME,
    SERVICE_ACCOUNT_SECRET,
    SERVICE_ACCOUNT_PROJECT_ID
  )

  # Create tracker with remote flags enabled
  tracker_with_flags = Mixpanel::Tracker.new(
    TOKEN,
    nil,  # error_handler
    credentials: credentials,
    remote_flags_config: {}  # Enable remote flags
  )

  # Test context (user properties for flag evaluation)
  context = {
    'distinct_id' => DISTINCT_ID,
    '$os' => 'Ruby',
    '$lib_version' => Mixpanel::VERSION
  }

  puts "Testing flag evaluation for user: #{DISTINCT_ID}"
  puts ""

  # Test 1: Get all variants (doesn't track exposure)
  puts "→ Getting all flags (no exposure tracking)..."
  all_variants = tracker_with_flags.remote_flags.get_all_variants(context)

  if all_variants
    puts "✅ Retrieved #{all_variants.size} flag(s):"
    all_variants.each do |flag_key, variant|
      value_str = variant.variant_value.is_a?(Hash) ?
        variant.variant_value.inspect[0..60] + "..." :
        variant.variant_value.inspect
      puts "   - #{flag_key}: #{value_str} (variant: #{variant.variant_key})"
    end
  elsif all_variants.nil?
    puts "⚠️  No flags returned (may indicate auth error or no flags configured)"
    puts ""
    puts "DEBUG INFO:"
    puts "  Token: #{TOKEN[0..10]}..."
    puts "  Project ID: #{SERVICE_ACCOUNT_PROJECT_ID}"
    puts "  Username: #{SERVICE_ACCOUNT_USERNAME}"
    puts "  Secret: #{SERVICE_ACCOUNT_SECRET[0..5]}...#{SERVICE_ACCOUNT_SECRET[-5..-1]}"
  end

  puts ""

  # Test 2: Get specific flag variant (tracks exposure)
  if all_variants && all_variants.any?
    flag_key = all_variants.keys.first
    puts "→ Getting specific flag: #{flag_key} (with exposure tracking)..."

    variant = tracker_with_flags.remote_flags.get_variant(
      flag_key,
      Mixpanel::Flags::SelectedVariant.new(variant_value: 'fallback-value'),
      context
    )

    puts "✅ Flag value: #{variant.variant_value.inspect}"
    puts "   Variant key: #{variant.variant_key}"
    if variant.experiment_id
      puts "   Experiment ID: #{variant.experiment_id}"
      puts "   Is active: #{variant.is_experiment_active}"
    end

    puts ""

    # Test 3: Boolean flag check (if flag value is boolean)
    if variant.variant_value.is_a?(TrueClass) || variant.variant_value.is_a?(FalseClass)
      puts "→ Checking if flag is enabled (boolean check)..."
      is_enabled = tracker_with_flags.remote_flags.is_enabled?(flag_key, context)
      puts "✅ Flag enabled: #{is_enabled}"
    end
  else
    puts "⚠️  No flags available to test individual flag operations"
    puts "   Create flags in Mixpanel UI to test get_variant and is_enabled"
  end

  # Shutdown to flush any pending events
  tracker_with_flags.remote_flags.shutdown

rescue => e
  puts "❌ Flags error: #{e.class} - #{e.message}"
  puts "   #{e.backtrace.first(10).join("\n   ")}"
end

puts ""
puts "=" * 80
puts "Test Complete"
puts "=" * 80
puts ""
puts "Notes:"
puts "- Check Mixpanel UI to verify events were tracked"
puts "- Import events appear in Events view (may take a few minutes)"
puts "- Flag exposure events tracked as '$feature_flag_called'"
puts ""
puts "Expected HTTP behavior:"
puts "  Import: POST /import?project_id=#{SERVICE_ACCOUNT_PROJECT_ID}"
puts "          Authorization: Basic <username:secret>"
puts "  Flags:  GET /flags?token=#{TOKEN}&project_id=#{SERVICE_ACCOUNT_PROJECT_ID}&..."
puts "          Authorization: Basic <username:secret>"
