#!/bin/bash
# Quick test runner using Docker (no Ruby installation needed)

set -e

cd "$(dirname "$0")"

echo "=========================================="
echo "Running Mixpanel Ruby SDK Tests in Docker"
echo "=========================================="
echo ""

# Check if Docker is available
if ! command -v docker &> /dev/null; then
    echo "❌ Docker not found. Please install Docker or install Ruby locally."
    echo ""
    echo "See TESTING.md for Ruby installation instructions."
    exit 1
fi

echo "Using Docker to run tests (Ruby 3.3)..."
echo ""

# Run tests in Docker container
docker run -it --rm \
    -v "$(pwd):/app" \
    -w /app \
    ruby:3.3-slim \
    bash -c '
        echo "Installing dependencies..."
        gem install bundler -v "~> 2.0" --no-document
        bundle install --quiet

        echo ""
        echo "Running tests..."
        echo "===================="

        # Run all tests
        bundle exec rspec --format documentation

        EXIT_CODE=$?

        echo ""
        echo "===================="
        if [ $EXIT_CODE -eq 0 ]; then
            echo "✅ All tests passed!"
        else
            echo "❌ Some tests failed"
            exit $EXIT_CODE
        fi
    '

echo ""
echo "=========================================="
echo "Test run complete"
echo "=========================================="
