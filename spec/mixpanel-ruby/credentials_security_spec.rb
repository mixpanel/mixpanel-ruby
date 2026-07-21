require 'mixpanel-ruby'
require 'json'

describe 'Credentials Security' do
  describe 'import with constructor credentials (recommended)' do
    it 'should NOT include credentials in message payload' do
      messages = []
      credentials = Mixpanel::ServiceAccountCredentials.new('test-user', 'test-secret', 'test-project')

      # Create tracker with credentials in constructor
      tracker = Mixpanel::Tracker.new('TOKEN', nil, credentials: credentials) do |type, message|
        messages << [type, message]
      end

      # Call import with nil api_key (recommended pattern)
      tracker.import(nil, 'user123', 'Test Event', {'prop' => 'value'})

      # Verify message was sent
      expect(messages.length).to eq(1)
      type, message_json = messages[0]
      expect(type).to eq(:import)

      # Parse the message
      message = JSON.parse(message_json)

      # CRITICAL: Credentials should NOT be in the message
      expect(message).not_to have_key('credentials')
      expect(message_json).not_to include('test-secret')
      expect(message_json).not_to include('test-user')

      # Message should only contain data
      expect(message).to have_key('data')
      expect(message['data']).to have_key('event')
      expect(message['data']['event']).to eq('Test Event')
    end

    it 'should NOT include credentials in buffered messages' do
      messages = []
      credentials = Mixpanel::ServiceAccountCredentials.new('test-user', 'test-secret', 'test-project')

      # Create buffered consumer with credentials
      consumer = Mixpanel::BufferedConsumer.new(nil, nil, nil, 5, credentials: credentials) do |type, message|
        messages << [type, message]
      end

      # Send multiple event messages (events are buffered, imports are not)
      5.times do |i|
        consumer.send!(:event, {'data' => {'event' => "Event #{i}"}}.to_json)
      end

      # Verify batched message was sent (auto-flushed when buffer reaches max_length)
      expect(messages.length).to eq(1)
      type, message_json = messages[0]

      # CRITICAL: Credentials should NOT be in the batched message
      expect(message_json).not_to include('credentials')
      expect(message_json).not_to include('test-secret')
      expect(message_json).not_to include('test-user')
    end
  end

  describe 'tracking events' do
    it 'should never include credentials in event messages' do
      messages = []
      credentials = Mixpanel::ServiceAccountCredentials.new('test-user', 'test-secret', 'test-project')

      tracker = Mixpanel::Tracker.new('TOKEN', nil, credentials: credentials) do |type, message|
        messages << [type, message]
      end

      # Track a regular event
      tracker.track('user123', 'Test Event', {'prop' => 'value'})

      # Verify message
      expect(messages.length).to eq(1)
      type, message_json = messages[0]
      expect(type).to eq(:event)

      # Credentials should NEVER be in event messages
      expect(message_json).not_to include('credentials')
      expect(message_json).not_to include('test-secret')
    end
  end

  describe 'legacy API key pattern' do
    it 'should include api_key in message but not credentials' do
      messages = []
      tracker = Mixpanel::Tracker.new('TOKEN') do |type, message|
        messages << [type, message]
      end

      # Use legacy API key pattern
      tracker.import('MY_API_KEY', 'user123', 'Test Event', {'prop' => 'value'})

      # Verify message
      expect(messages.length).to eq(1)
      type, message_json = messages[0]
      message = JSON.parse(message_json)

      # API key should be in message (legacy pattern)
      expect(message).to have_key('api_key')
      expect(message['api_key']).to eq('MY_API_KEY')

      # But credentials should NOT be
      expect(message).not_to have_key('credentials')
    end
  end
end
