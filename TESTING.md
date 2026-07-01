# How to Run Tests

This guide explains how to set up and run the tests for the Mixpanel Ruby SDK.

## Prerequisites

You need Ruby 3.0.0 or higher installed. This project requires Ruby with bundler.

### Installing Ruby

**Option 1: Using rbenv (Recommended)**

```bash
# Install rbenv
curl -fsSL https://github.com/rbenv/rbenv-installer/raw/main/bin/rbenv-installer | bash

# Add to your shell
echo 'eval "$(rbenv init - bash)"' >> ~/.bashrc
source ~/.bashrc

# Install Ruby 3.0 or higher
rbenv install 3.3.0
rbenv local 3.3.0

# Verify
ruby --version  # Should show Ruby 3.3.0 or higher
```

**Option 2: Using apt (Ubuntu/Debian)**

```bash
sudo apt-get update
sudo apt-get install ruby-full ruby-bundler
ruby --version
```

**Option 3: Using asdf**

```bash
# If you have asdf installed
asdf plugin add ruby
asdf install ruby 3.3.0
asdf local ruby 3.3.0
```

## Setup

Once Ruby is installed:

```bash
cd /home/john_la/mixpanel-ruby

# Install bundler if not already installed
gem install bundler

# Install dependencies
bundle install
```

## Running Tests

### Run All Tests

```bash
# Using rake (recommended)
bundle exec rake

# Or using rspec directly
bundle exec rspec
```

### Run Specific Test Files

```bash
# Run only consumer tests
bundle exec rspec spec/mixpanel-ruby/consumer_spec.rb

# Run only events tests
bundle exec rspec spec/mixpanel-ruby/events_spec.rb

# Run only the service account test
bundle exec rspec spec/mixpanel-ruby/consumer_spec.rb:39
```

### Run Tests with Verbose Output

```bash
# Show test names as they run
bundle exec rspec --format documentation

# Run specific test with full details
bundle exec rspec spec/mixpanel-ruby/consumer_spec.rb:39 --format documentation
```

### Run Tests for Service Account Changes

```bash
# Run the consumer test that verifies Basic Auth and query params
bundle exec rspec spec/mixpanel-ruby/consumer_spec.rb:39 -fd

# Run the events test that verifies credentials are passed correctly
bundle exec rspec spec/mixpanel-ruby/events_spec.rb:79 -fd
```

## Expected Output

When tests pass, you should see:

```
Mixpanel::Consumer
  raw consumer
    should send a request to api.mixpanel.com/import with service account credentials

Finished in 0.01234 seconds
1 example, 0 failures
```

## Key Tests for Service Account Authentication

### 1. Consumer Test (`spec/mixpanel-ruby/consumer_spec.rb:39`)

This test verifies that:
- ✅ Basic Auth header is set with `username:secret`
- ✅ `project_id` is added as a query parameter
- ✅ POST body contains only `data` and `verbose` (no credentials)

### 2. Events Test (`spec/mixpanel-ruby/events_spec.rb:79`)

This test verifies that:
- ✅ Credentials are passed to the consumer
- ✅ Message structure includes credentials hash
- ✅ Legacy API key path still works

## Troubleshooting

### "bundle: command not found"

```bash
gem install bundler
```

### "Could not find gem 'rspec'"

```bash
bundle install
```

### "Wrong Ruby version"

```bash
# Check current version
ruby --version

# If too old, install newer version (see Installing Ruby above)
```

### WebMock Errors

If you see errors about WebMock, ensure you have the correct version:

```bash
bundle update webmock
```

## Alternative: Docker

If you don't want to install Ruby locally, you can use Docker:

```bash
# Build and run tests in Docker
docker run -it --rm -v "$PWD:/app" -w /app ruby:3.3 bash -c "
  gem install bundler && 
  bundle install && 
  bundle exec rspec
"
```

## CI/CD

Tests should also run in CI. Check `.github/workflows/` for automated test runs.

## What We Changed

The tests were updated to verify the new service account authentication behavior:

**Before:**
```ruby
expect(WebMock).to have_requested(:post, 'https://api.mixpanel.com/import').
  with(:body => {
    'data' => '...',
    'username' => 'test-user',        # ❌ Wrong
    'secret' => 'test-secret',        # ❌ Wrong
    'project_id' => 'test-project-123', # ❌ Wrong
    'verbose' => '1'
  })
```

**After:**
```ruby
expect(WebMock).to have_requested(:post, 'https://api.mixpanel.com/import?project_id=test-project-123').
  with(
    :body => {
      'data' => '...',
      'verbose' => '1'  # ✅ Only data and verbose
    },
    :headers => {
      'Authorization' => 'Basic ' + Base64.strict_encode64('test-user:test-secret')  # ✅ Auth header
    }
  )
```

This matches the Python SDK implementation (PR #175).
