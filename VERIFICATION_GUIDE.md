# Service Account Authentication Verification Guide

This document describes the implementation and expected HTTP behavior for service account authentication in the Ruby SDK.

## Implementation Summary

The Ruby SDK now matches the Python SDK implementation (PR #175):

### 1. Import Endpoint (`/import`)

**HTTP Request Structure:**
```
POST /import?project_id=132990 HTTP/1.1
Host: api.mixpanel.com
Authorization: Basic am9obmxhLWFkbWluLjVkYjE4YS5tcC1zZXJ2aWNlLWFjY291bnQ6QnpTdzNyQWpGRmlmaDY0RVlHVDFSVklGZ3RXTDNiN0Y=
Content-Type: application/x-www-form-urlencoded

data=eyJldmVudCI6IlRlc3QiLCAicHJvcGVydGllcyI6IHsuLi59fQ==&verbose=1
```

**Key Points:**
- ✅ Uses HTTP Basic Auth header with `username:secret`
- ✅ Adds `project_id` as query parameter
- ✅ Does NOT include credentials in POST body
- ✅ Only applies to `:import` type (not `:event`, `:profile_update`, or `:group_update`)

**Code Location:** `lib/mixpanel-ruby/consumer.rb:131-148`

### 2. Flags Endpoints (`/flags`, `/flags/definitions`)

**HTTP Request Structure:**
```
GET /flags?token=9c4e9a6caf9f429a7e3821141fc769b7&project_id=132990&lib=ruby&context=%7B%22distinct_id%22%3A%22user123%22%7D HTTP/1.1
Host: api.mixpanel.com
Authorization: Basic am9obmxhLWFkbWluLjVkYjE4YS5tcC1zZXJ2aWNlLWFjY291bnQ6QnpTdzNyQWpGRmlmaDY0RVlHVDFSVklGZ3RXTDNiN0Y=
Content-Type: application/json
```

**Key Points:**
- ✅ Uses HTTP Basic Auth header with `username:secret`
- ✅ Adds `project_id` as query parameter
- ✅ Token still included in query params
- ✅ Uses GET method

**Code Location:** `lib/mixpanel-ruby/flags/flags_provider.rb:42-47`

## Test Credentials (Provided)

```bash
Service Account Username: johnla-admin.5db18a.mp-service-account
Service Account Secret: BzSw3rAjFFifh64EYGT1RVIFgtWL3b7F
Project ID: 132990
Project Token: 9c4e9a6caf9f429a7e3821141fc769b7
```

## How to Test

### Option 1: Using the Ruby SDK (requires Ruby installed)

```bash
export MIXPANEL_TOKEN='9c4e9a6caf9f429a7e3821141fc769b7'
export MIXPANEL_SA_USERNAME='johnla-admin.5db18a.mp-service-account'
export MIXPANEL_SA_SECRET='BzSw3rAjFFifh64EYGT1RVIFgtWL3b7F'
export MIXPANEL_SA_PROJECT_ID='132990'

ruby test_import_simple.rb
```

### Option 2: Using curl (HTTP verification)

**Test Import Endpoint:**

```bash
# Prepare variables
TOKEN='9c4e9a6caf9f429a7e3821141fc769b7'
USERNAME='johnla-admin.5db18a.mp-service-account'
SECRET='BzSw3rAjFFifh64EYGT1RVIFgtWL3b7F'
PROJECT_ID='132990'

# Create test event
DISTINCT_ID="test-$(date +%s)"
TIMESTAMP=$(date +%s)

EVENT_JSON="{\"event\":\"Test\",\"properties\":{\"distinct_id\":\"$DISTINCT_ID\",\"token\":\"$TOKEN\",\"time\":$TIMESTAMP}}"
ENCODED_DATA=$(echo -n "$EVENT_JSON" | base64 | tr -d '\n')

# Make request
curl -v -X POST \
  "https://api.mixpanel.com/import?project_id=$PROJECT_ID" \
  -u "$USERNAME:$SECRET" \
  -d "data=$ENCODED_DATA" \
  -d "verbose=1"
```

**Test Flags Endpoint:**

```bash
CONTEXT='{"distinct_id":"user123"}'
ENCODED_CONTEXT=$(echo -n "$CONTEXT" | python3 -c "import sys, urllib.parse; print(urllib.parse.quote(sys.stdin.read()))")

curl -v -X GET \
  "https://api.mixpanel.com/flags?token=$TOKEN&project_id=$PROJECT_ID&lib=ruby&context=$ENCODED_CONTEXT" \
  -u "$USERNAME:$SECRET"
```

### Option 3: Manual HTTP Inspection

Use a tool like `mitmproxy`, `charles`, or browser DevTools to inspect the actual HTTP requests made by the Ruby SDK.

**Expected to see:**
1. Authorization header: `Basic <base64(username:secret)>`
2. Query parameter: `?project_id=132990`
3. POST body for import: Only `data` and `verbose`, NO credentials

## What Changed from Previous Implementation

### Before (Incorrect):
```ruby
# Consumer sent credentials in POST body
form_data = {
  'data' => encoded_data,
  'username' => credentials['username'],      # ❌ Wrong
  'secret' => credentials['secret'],          # ❌ Wrong
  'project_id' => credentials['project_id'],  # ❌ Wrong
  'verbose' => 1
}
```

### After (Correct):
```ruby
# Consumer uses Basic Auth + query param
uri.query = "project_id=#{credentials['project_id']}"  # ✅ Query param
request.basic_auth(credentials['username'], credentials['secret'])  # ✅ Auth header

form_data = {
  'data' => encoded_data,  # ✅ Only data and verbose
  'verbose' => 1
}
```

## Files Modified

1. `lib/mixpanel-ruby/consumer.rb` - Import endpoint authentication
2. `lib/mixpanel-ruby/flags/flags_provider.rb` - Flags endpoint project_id
3. `spec/mixpanel-ruby/consumer_spec.rb` - Updated test expectations
4. `spec/mixpanel-ruby/events_spec.rb` - Added credentials require

## Backward Compatibility

- ✅ Legacy API key authentication still works for import endpoint
- ✅ Token-based authentication still works for flags endpoint
- ✅ Service account credentials are optional (graceful fallback)

## Next Steps

To verify the implementation works with production:

1. Run one of the test scripts with your credentials
2. Check Mixpanel UI for the imported event
3. Verify flags API returns expected results
4. Monitor for any authentication errors

Expected success indicators:
- Import: HTTP 200 with `{"status": 1}`
- Flags: HTTP 200 with JSON containing flags data
