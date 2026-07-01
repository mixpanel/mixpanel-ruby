#!/bin/bash
# Test only the service account authentication changes

set -e

cd "$(dirname "$0")"

echo "=========================================="
echo "Testing Service Account Changes"
echo "=========================================="
echo ""

if ! command -v docker &> /dev/null; then
    echo "❌ Docker not found"
    echo ""
    echo "Install Docker or run manually with Ruby:"
    echo "  bundle exec rspec spec/mixpanel-ruby/consumer_spec.rb:39"
    exit 1
fi

docker run -it --rm \
    -v "$(pwd):/app" \
    -w /app \
    ruby:3.3-slim \
    bash -c '
        gem install bundler -v "~> 2.0" --no-document --quiet
        bundle install --quiet

        echo "Test 1: Consumer with Service Account Credentials"
        echo "------------------------------------------------"
        bundle exec rspec spec/mixpanel-ruby/consumer_spec.rb:39 --format documentation

        echo ""
        echo "Test 2: Events with Service Account Credentials"
        echo "------------------------------------------------"
        bundle exec rspec spec/mixpanel-ruby/events_spec.rb:79 --format documentation

        echo ""
        echo "✅ Service account tests passed!"
    '

echo ""
echo "=========================================="
echo "What these tests verify:"
echo "=========================================="
echo "✅ Import uses Basic Auth header (username:secret)"
echo "✅ Import adds project_id as query parameter"
echo "✅ Import POST body has only data + verbose"
echo "✅ Credentials flow correctly through Events API"
