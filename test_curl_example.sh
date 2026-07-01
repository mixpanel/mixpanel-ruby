#!/bin/bash
# Example curl commands showing the expected HTTP behavior

set -e

# Check environment variables
if [ -z "$MIXPANEL_TOKEN" ] || [ -z "$MIXPANEL_SA_USERNAME" ] || [ -z "$MIXPANEL_SA_SECRET" ] || [ -z "$MIXPANEL_SA_PROJECT_ID" ]; then
  echo "Please set environment variables:"
  echo ""
  echo "export MIXPANEL_TOKEN='your-project-token'"
  echo "export MIXPANEL_SA_USERNAME='your-service-account-username'"
  echo "export MIXPANEL_SA_SECRET='your-service-account-secret'"
  echo "export MIXPANEL_SA_PROJECT_ID='your-project-id'"
  echo ""
  exit 1
fi

echo "=========================================="
echo "Mixpanel Service Account - Raw HTTP Test"
echo "=========================================="
echo ""

# Prepare test data
DISTINCT_ID="curl-test-user-$(date +%s)"
TIMESTAMP=$(( $(date +%s) - 3600 ))  # 1 hour ago

# Create event data
EVENT_DATA=$(cat <<EOF
{
  "event": "Curl Test Event",
  "properties": {
    "distinct_id": "$DISTINCT_ID",
    "token": "$MIXPANEL_TOKEN",
    "time": $TIMESTAMP,
    "test": true,
    "source": "curl-test"
  }
}
EOF
)

# Base64 encode the event data (URL-safe)
ENCODED_DATA=$(echo -n "$EVENT_DATA" | base64 | tr -d '\n')

echo "Test Configuration:"
echo "  Project ID: $MIXPANEL_SA_PROJECT_ID"
echo "  Username: $MIXPANEL_SA_USERNAME"
echo "  Distinct ID: $DISTINCT_ID"
echo ""

echo "=========================================="
echo "TEST 1: Import Endpoint"
echo "=========================================="
echo ""
echo "Expected behavior:"
echo "  - URL: /import?project_id=$MIXPANEL_SA_PROJECT_ID"
echo "  - Authorization: Basic \$(base64 username:secret)"
echo "  - Body: data=\$ENCODED_DATA&verbose=1"
echo ""

# Create Basic Auth header
AUTH_HEADER=$(echo -n "$MIXPANEL_SA_USERNAME:$MIXPANEL_SA_SECRET" | base64)

echo "Sending request..."
RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}" \
  -X POST \
  "https://api.mixpanel.com/import?project_id=$MIXPANEL_SA_PROJECT_ID" \
  -H "Authorization: Basic $AUTH_HEADER" \
  -d "data=$ENCODED_DATA" \
  -d "verbose=1")

HTTP_CODE=$(echo "$RESPONSE" | grep "HTTP_CODE:" | cut -d: -f2)
BODY=$(echo "$RESPONSE" | grep -v "HTTP_CODE:")

echo ""
echo "Response:"
echo "  HTTP Status: $HTTP_CODE"
echo "  Body: $BODY"
echo ""

if [ "$HTTP_CODE" = "200" ]; then
  if echo "$BODY" | grep -q '"status":1'; then
    echo "✅ Import successful!"
  else
    echo "⚠️  Import returned 200 but status != 1"
    echo "   Response: $BODY"
  fi
else
  echo "❌ Import failed with HTTP $HTTP_CODE"
  echo "   Response: $BODY"
fi

echo ""
echo "=========================================="
echo "TEST 2: Flags Endpoint"
echo "=========================================="
echo ""
echo "Expected behavior:"
echo "  - URL: /flags?token=$MIXPANEL_TOKEN&project_id=$MIXPANEL_SA_PROJECT_ID"
echo "  - Authorization: Basic \$(base64 username:secret)"
echo "  - Method: GET"
echo ""

# Prepare context for flags request
CONTEXT=$(cat <<EOF
{"distinct_id":"$DISTINCT_ID","\$os":"Linux"}
EOF
)

echo "Sending request..."
RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}" \
  -X GET \
  "https://api.mixpanel.com/flags?token=$MIXPANEL_TOKEN&project_id=$MIXPANEL_SA_PROJECT_ID&lib=ruby&context=$(echo -n "$CONTEXT" | jq -sRr @uri)" \
  -H "Authorization: Basic $AUTH_HEADER")

HTTP_CODE=$(echo "$RESPONSE" | grep "HTTP_CODE:" | cut -d: -f2)
BODY=$(echo "$RESPONSE" | grep -v "HTTP_CODE:")

echo ""
echo "Response:"
echo "  HTTP Status: $HTTP_CODE"
echo "  Body: $BODY"
echo ""

if [ "$HTTP_CODE" = "200" ]; then
  echo "✅ Flags endpoint successful!"
  NUM_FLAGS=$(echo "$BODY" | jq '.flags | length' 2>/dev/null || echo "?")
  echo "   Number of flags: $NUM_FLAGS"
else
  echo "❌ Flags failed with HTTP $HTTP_CODE"
  echo "   Response: $BODY"
fi

echo ""
echo "=========================================="
echo "Summary"
echo "=========================================="
echo ""
echo "Both requests use HTTP Basic Auth with username:secret"
echo "Both requests include project_id as a query parameter"
echo "Import: POST with form data (data + verbose)"
echo "Flags:  GET with query params (token + project_id + context)"
