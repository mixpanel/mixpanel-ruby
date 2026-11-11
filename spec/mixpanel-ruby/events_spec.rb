require 'spec_helper'
require 'time'

require 'mixpanel-ruby/events.rb'
require 'mixpanel-ruby/version.rb'
require 'mixpanel-ruby/credentials.rb'

describe Mixpanel::Events do
  before(:each) do
    @time_now = Time.parse('Jun 6 1972, 16:23:04')
    allow(Time).to receive(:now).and_return(@time_now)

    @log = []
    @events = Mixpanel::Events.new('TEST TOKEN') do |type, message|
      @log << [type, JSON.load(message)]
    end
  end

  it 'should send a well formed track/ message' do
    @events.track('TEST ID', 'Test Event', {
        'Circumstances' => 'During a test'
    })
    expect(@log).to eq([[:event, 'data' => {
        'event' => 'Test Event',
        'properties' => {
            'Circumstances' => 'During a test',
            'distinct_id' => 'TEST ID',
            'mp_lib' => 'ruby',
            '$lib_version' => Mixpanel::VERSION,
            'token' => 'TEST TOKEN',
            'time' => @time_now.to_i * 1000
        }
    }]])
  end

  it 'should send a well formed import/ message' do
    @events.import('API_KEY', 'TEST ID', 'Test Event', {
        'Circumstances' => 'During a test'
    })
    expect(@log).to eq([[:import, {
        'api_key' => 'API_KEY',
        'data' => {
            'event' => 'Test Event',
            'properties' => {
                'Circumstances' => 'During a test',
                'distinct_id' => 'TEST ID',
                'mp_lib' => 'ruby',
                '$lib_version' => Mixpanel::VERSION,
                'token' => 'TEST TOKEN',
                'time' => @time_now.to_i * 1000
            }
        }
    } ]])
  end

  it 'should allow users to pass timestamp for import' do
    older_time = Time.parse('Jun 6 1971, 16:23:04')
    @events.import('API_KEY', 'TEST ID', 'Test Event', {
        'Circumstances' => 'During a test',
        'time' => older_time.to_i,
    })
    expect(@log).to eq([[:import, {
        'api_key' => 'API_KEY',
        'data' => {
            'event' => 'Test Event',
            'properties' => {
                'Circumstances' => 'During a test',
                'distinct_id' => 'TEST ID',
                'mp_lib' => 'ruby',
                '$lib_version' => Mixpanel::VERSION,
                'token' => 'TEST TOKEN',
                'time' => older_time.to_i,
            }
        }
    } ]])
  end

  it 'should send a well formed import/ message with service account credentials' do
    credentials = Mixpanel::ServiceAccountCredentials.new('test-user', 'test-secret', 'test-project-123')

    # Create new Events instance with credentials in constructor
    events_with_creds = Mixpanel::Events.new('TEST TOKEN', nil, credentials: credentials) do |type, message|
      @log << [type, JSON.load(message)]
    end

    # New API: pass nil for api_key, credentials come from instance
    events_with_creds.import(nil, 'TEST ID', 'Test Event', {
        'Circumstances' => 'During a test'
    })

    expect(@log.length).to eq(1)
    expect(@log[0][0]).to eq(:import)

    message = @log[0][1]
    # Credentials should NOT be in message (secure API)
    expect(message).not_to have_key('credentials')
    expect(message).not_to have_key('api_key')
    expect(message['data']).to eq({
        'event' => 'Test Event',
        'properties' => {
            'Circumstances' => 'During a test',
            'distinct_id' => 'TEST ID',
            'mp_lib' => 'ruby',
            '$lib_version' => Mixpanel::VERSION,
            'token' => 'TEST TOKEN',
            'time' => @time_now.to_i * 1000
        }
    })
  end

  it 'should raise ArgumentError when import is called without authentication' do
    # Create Events without credentials
    events = Mixpanel::Events.new('TEST TOKEN') do |type, message|
      @log << [type, JSON.load(message)]
    end

    # Try to import with nil api_key and no credentials
    expect {
      events.import(nil, 'TEST ID', 'Test Event', {})
    }.to raise_error(ArgumentError, /import requires authentication/)
  end

  describe 'import_events' do
    it 'should send a well formed import/ message with constructor credentials' do
      credentials = Mixpanel::ServiceAccountCredentials.new('test-user', 'test-secret', 'test-project-123')

      events_with_creds = Mixpanel::Events.new('TEST TOKEN', nil, credentials: credentials) do |type, message|
        @log << [type, JSON.load(message)]
      end

      # Clean API - no nil!
      events_with_creds.import_events('TEST ID', 'Test Event', {
        'Circumstances' => 'During a test'
      })

      expect(@log.length).to eq(1)
      expect(@log[0][0]).to eq(:import)

      message = @log[0][1]
      # Credentials should NOT be in message
      expect(message).not_to have_key('credentials')
      expect(message).not_to have_key('api_key')
      expect(message['data']).to eq({
        'event' => 'Test Event',
        'properties' => {
          'Circumstances' => 'During a test',
          'distinct_id' => 'TEST ID',
          'mp_lib' => 'ruby',
          '$lib_version' => Mixpanel::VERSION,
          'token' => 'TEST TOKEN',
          'time' => @time_now.to_i * 1000
        }
      })
    end

    it 'should raise ArgumentError when called without constructor credentials' do
      events = Mixpanel::Events.new('TEST TOKEN') do |type, message|
        @log << [type, JSON.load(message)]
      end

      expect {
        events.import_events('TEST ID', 'Test Event', {})
      }.to raise_error(ArgumentError, /import_events requires credentials in constructor/)
    end
  end

  describe 'warnings' do
    it 'should warn when credentials are passed with a custom block' do
      credentials = Mixpanel::ServiceAccountCredentials.new('user', 'secret', 'project')

      expect {
        Mixpanel::Events.new('TEST TOKEN', nil, credentials: credentials) do |type, message|
          # Custom block
        end
      }.to output(/credentials passed to Events\/Tracker are ignored/).to_stderr
    end

    it 'should not warn when credentials are passed without a block' do
      credentials = Mixpanel::ServiceAccountCredentials.new('user', 'secret', 'project')

      expect {
        Mixpanel::Events.new('TEST TOKEN', nil, credentials: credentials)
      }.not_to output.to_stderr
    end

    it 'should warn when using deprecated api_key in import' do
      events = Mixpanel::Events.new('TEST TOKEN') do |type, message|
        @log << [type, JSON.load(message)]
      end

      expect {
        events.import('API_KEY', 'TEST ID', 'Test Event', {})
      }.to output(/DEPRECATION.*api_key to import\(\) is deprecated/).to_stderr

      # Second call should also warn
      expect {
        events.import('API_KEY', 'TEST ID', 'Test Event 2', {})
      }.to output(/DEPRECATION.*api_key to import\(\) is deprecated/).to_stderr
    end

    it 'should warn when using import(nil, ...) with credentials' do
      credentials = Mixpanel::ServiceAccountCredentials.new('user', 'secret', 'project')
      events = Mixpanel::Events.new('TEST TOKEN', nil, credentials: credentials) do |type, message|
        @log << [type, JSON.load(message)]
      end

      expect {
        events.import(nil, 'TEST ID', 'Test Event', {})
      }.to output(/DEPRECATION.*import\(nil, \.\.\.\) is deprecated.*import_events/).to_stderr

      # Second call should also warn
      expect {
        events.import(nil, 'TEST ID', 'Test Event 2', {})
      }.to output(/DEPRECATION.*import\(nil, \.\.\.\) is deprecated.*import_events/).to_stderr
    end

    it 'should not warn when using import_events' do
      credentials = Mixpanel::ServiceAccountCredentials.new('user', 'secret', 'project')
      events = Mixpanel::Events.new('TEST TOKEN', nil, credentials: credentials) do |type, message|
        @log << [type, JSON.load(message)]
      end

      expect {
        events.import_events('TEST ID', 'Test Event', {})
      }.not_to output(/DEPRECATION/).to_stderr
    end
  end

  describe 'import failures' do
    let(:credentials) { Mixpanel::ServiceAccountCredentials.new('user', 'secret', 'project') }
    let(:failing_sink) do
      proc { |_type, _message| raise Mixpanel::ServerError, "Could not write to Mixpanel, server responded with 401" }
    end

    it 'returns false and warns on stderr with the default error handler' do
      events = Mixpanel::Events.new('TEST TOKEN', nil, credentials: nil, &failing_sink)
      events.instance_variable_set(:@credentials, credentials)

      result = nil
      expect {
        result = events.import_events('TEST ID', 'Test Event', {})
      }.to output(/\[Mixpanel\] import failed; the event may not have been stored: .*401/).to_stderr
      expect(result).to be false
    end

    it 'says the outcome is unknown when the import fails with a connection error' do
      events = Mixpanel::Events.new('TEST TOKEN') do |_type, _message|
        raise Mixpanel::ConnectionError, 'Could not connect to Mixpanel, with error "Net::ReadTimeout".'
      end
      events.instance_variable_set(:@credentials, credentials)

      result = nil
      expect {
        result = events.import_events('TEST ID', 'Test Event', {})
      }.to output(/\[Mixpanel\] import failed; the event may not have been stored: .*ReadTimeout/).to_stderr
      expect(result).to be false
    end

    it 'prints the failure on a single line even when the server body has newlines' do
      events = Mixpanel::Events.new('TEST TOKEN') do |_type, _message|
        raise Mixpanel::ServerError, "Could not write to Mixpanel, server responded with 401 returning: '{\"status\":0}\n'"
      end
      events.instance_variable_set(:@credentials, credentials)

      expect {
        events.import_events('TEST ID', 'Test Event', {})
      }.to output(/\A\[Mixpanel\] import failed[^\n]*\n\z/).to_stderr
    end

    it 'passes the error to a custom handler without printing the import warning' do
      handler = Class.new(Mixpanel::ErrorHandler) do
        attr_reader :errors
        def handle(error)
          (@errors ||= []) << error
        end
      end.new
      events = Mixpanel::Events.new('TEST TOKEN', handler, &failing_sink)
      events.instance_variable_set(:@credentials, credentials)

      result = nil
      expect {
        result = events.import_events('TEST ID', 'Test Event', {})
      }.not_to output(/import failed/).to_stderr
      expect(result).to be false
      expect(handler.errors.map(&:class)).to eq([Mixpanel::ServerError])
    end

    it 'keeps track failures silent with the default error handler' do
      events = Mixpanel::Events.new('TEST TOKEN', &failing_sink)

      result = nil
      expect {
        result = events.track('TEST ID', 'Test Event', {})
      }.not_to output.to_stderr
      expect(result).to be false
    end

    it 'does not warn when the import succeeds' do
      events = Mixpanel::Events.new('TEST TOKEN') { |_type, _message| true }
      events.instance_variable_set(:@credentials, credentials)

      expect {
        expect(events.import_events('TEST ID', 'Test Event', {})).to be true
      }.not_to output.to_stderr
    end
  end
end
