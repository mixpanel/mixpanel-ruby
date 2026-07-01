#!/usr/bin/env python3
"""
Verify the HTTP implementation matches expected behavior
"""

import requests
import base64
import json
import time
from urllib.parse import urlencode

# Credentials
TOKEN = '9c4e9a6caf9f429a7e3821141fc769b7'
USERNAME = 'johnla-admin.5db18a.mp-service-account'
SECRET = 'BzSw3rAjFFifh64EYGT1RVIFgtWL3b7F'
PROJECT_ID = '132990'

print("=" * 70)
print("Mixpanel Service Account HTTP Verification")
print("=" * 70)
print()

# Test 1: Import Endpoint
print("TEST 1: Import Endpoint")
print("-" * 70)

distinct_id = f"verify-test-{int(time.time())}"
historical_time = int(time.time()) - 3600

event_data = {
    "event": "Service Account Import Test",
    "properties": {
        "distinct_id": distinct_id,
        "token": TOKEN,
        "time": historical_time,
        "test": True,
        "source": "http-verification"
    }
}

encoded_data = base64.b64encode(json.dumps(event_data).encode()).decode()

print(f"Request URL: https://api.mixpanel.com/import?project_id={PROJECT_ID}")
print(f"Auth: Basic {USERNAME}:<secret>")
print(f"Distinct ID: {distinct_id}")
print()

response = requests.post(
    f"https://api.mixpanel.com/import?project_id={PROJECT_ID}",
    auth=(USERNAME, SECRET),
    data={
        'data': encoded_data,
        'verbose': '1'
    }
)

print(f"Response Status: {response.status_code}")
print(f"Response Body: {response.text}")

if response.status_code == 200:
    try:
        result = response.json()
        if result.get('status') == 1:
            print("✅ Import successful!")
        else:
            print(f"⚠️  Import returned status: {result.get('status')}")
            if result.get('error'):
                print(f"   Error: {result.get('error')}")
    except:
        print("⚠️  Could not parse JSON response")
else:
    print(f"❌ Import failed with HTTP {response.status_code}")

print()
print()

# Test 2: Flags Endpoint
print("TEST 2: Flags Endpoint")
print("-" * 70)

context = {
    "distinct_id": distinct_id,
    "$os": "Python"
}

params = {
    'token': TOKEN,
    'project_id': PROJECT_ID,
    'lib': 'ruby',
    'context': json.dumps(context)
}

print(f"Request URL: https://api.mixpanel.com/flags?{urlencode(params)}")
print(f"Auth: Basic {USERNAME}:<secret>")
print(f"Context: {context}")
print()

response = requests.get(
    f"https://api.mixpanel.com/flags",
    params=params,
    auth=(USERNAME, SECRET)
)

print(f"Response Status: {response.status_code}")
print(f"Response Body: {response.text[:500]}...")  # Truncate if long

if response.status_code == 200:
    try:
        result = response.json()
        flags = result.get('flags', {})
        print(f"✅ Flags endpoint successful!")
        print(f"   Number of flags: {len(flags)}")
        if flags:
            print("   Flags:")
            for flag_key, flag_data in flags.items():
                print(f"     - {flag_key}: {flag_data.get('variant_value')}")
    except:
        print("⚠️  Could not parse JSON response")
else:
    print(f"❌ Flags failed with HTTP {response.status_code}")

print()
print("=" * 70)
print("Summary")
print("=" * 70)
print()
print("✅ Both endpoints use HTTP Basic Auth (username:secret)")
print("✅ Both endpoints include project_id as query parameter")
print("✅ Import POST body contains only 'data' and 'verbose'")
print("✅ Flags uses GET with query parameters")
print()
print("This matches the Python SDK implementation (PR #175)")
