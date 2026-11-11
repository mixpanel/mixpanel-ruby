require 'base64'
require 'cgi'
require 'json'
require 'mixpanel-ruby'
require 'uri'

describe Mixpanel::Tracker do
  before(:each) do
    @time_now = Time.parse('Jun 6 1972, 16:23:04')
    allow(Time).to receive(:now).and_return(@time_now)
  end

  describe 'import rejected by the server (GitHub #106)' do
    before(:each) { WebMock.reset! }

    it 'returns true, sends Basic Auth and project_id, and prints nothing when /import accepts the event' do
      stub_request(:post, 'https://api.mixpanel.com/import?project_id=123').
        to_return(status: 200, body: '{"code": 200, "num_records_imported": 1, "status": 1}')
      credentials = Mixpanel::ServiceAccountCredentials.new('sa-user', 'sa-secret', 123)
      tracker = Mixpanel::Tracker.new('TEST TOKEN', credentials: credentials)

      result = nil
      expect {
        result = tracker.import_events('ID', 'Import', { 'time' => 1369353600 })
      }.not_to output.to_stderr
      expect(result).to be true

      expect(WebMock).to have_requested(:post, 'https://api.mixpanel.com/import?project_id=123').
        with(basic_auth: ['sa-user', 'sa-secret']) { |req|
          form = URI.decode_www_form(req.body).to_h
          payload = JSON.parse(Base64.decode64(form['data']))
          !form.key?('api_key') && payload['event'] == 'Import' &&
            payload['properties']['distinct_id'] == 'ID' && payload['properties']['time'] == 1369353600
        }
    end

    it 'returns false and warns when /import rejects service account credentials' do
      stub_request(:post, 'https://api.mixpanel.com/import?project_id=123').
        to_return(status: 401, body: '{"error": "Invalid credentials", "status": 0}')
      credentials = Mixpanel::ServiceAccountCredentials.new('user', 'bad-secret', 123)
      tracker = Mixpanel::Tracker.new('TEST TOKEN', credentials: credentials)

      result = nil
      expect {
        result = tracker.import_events('ID', 'Import', { 'time' => 1369353600 })
      }.to output(/\[Mixpanel\] import failed; the event was rejected: .*401/).to_stderr
      expect(result).to be false
    end

    it 'returns false and warns when /import rejects a legacy api_key' do
      stub_request(:post, 'https://api.mixpanel.com/import').
        to_return(status: 401, body: '{"error": "Unauthorized", "status": 0}')
      tracker = Mixpanel::Tracker.new('TEST TOKEN')

      result = nil
      expect {
        result = tracker.import('API_KEY', 'ID', 'Import', { 'time' => 1369353600 })
      }.to output(/may be rejected by Mixpanel's \/import endpoint.*\[Mixpanel\] import failed; the event was rejected/m).to_stderr
      expect(result).to be false
    end
  end

  it 'should send an alias message to mixpanel no matter what the consumer is' do
    WebMock.reset!
    stub_request(:any, 'https://api.mixpanel.com/track').to_return({:body => '{"status": 1, "error": null}'})
    mixpanel = Mixpanel::Tracker.new('TEST TOKEN') {|*args| }
    mixpanel.alias('TEST ALIAS', 'TEST ID')

    expect(WebMock).to have_requested(:post, 'https://api.mixpanel.com/track').
      with(:body => {:data => 'eyJldmVudCI6IiRjcmVhdGVfYWxpYXMiLCJwcm9wZXJ0aWVzIjp7ImRpc3RpbmN0X2lkIjoiVEVTVCBJRCIsImFsaWFzIjoiVEVTVCBBTElBUyIsInRva2VuIjoiVEVTVCBUT0tFTiJ9fQ==', 'verbose' => '1'})
  end

  it 'should generate pixel tracking urls correctly' do
    mixpanel = Mixpanel::Tracker.new('TEST TOKEN')
    event = 'TEST EVENT'
    properties = {'Circumstances' => 'During test'}
    default_properties = {
      'distinct_id' => 'TEST_ID',
      'mp_lib' => 'ruby',
      '$lib_version' => Mixpanel::VERSION,
      'token' => 'TEST TOKEN',
      'time' => @time_now.to_i * 1000
    }
    expected_data = {'event' => event, 'properties' => properties.merge(default_properties)}

    url_string = mixpanel.generate_tracking_url('TEST_ID', event, properties)

    url = URI(url_string)
    expect(url.scheme).to eq('https')
    expect(url.host).to eq('api.mixpanel.com')
    expect(url.path).to eq('/track/')

    parsed_query = CGI.parse(url.query)
    expect(parsed_query['ip'][0]).to eq('1')
    expect(parsed_query['img'][0]).to eq('1')

    data = JSON.parse(Base64.urlsafe_decode64(parsed_query['data'][0]))
    expect(data).to eq(expected_data)
  end

  it 'should send a request to the track api with the default consumer' do
    WebMock.reset!
    stub_request(:any, 'https://api.mixpanel.com/track').to_return({:body => '{"status": 1, "error": null}'})
    stub_request(:any, 'https://api.mixpanel.com/engage').to_return({:body => '{"status": 1, "error": null}'})
    mixpanel = Mixpanel::Tracker.new('TEST TOKEN')

    mixpanel.track('TEST ID', 'TEST EVENT', {'Circumstances' => 'During test'})

    body = nil
    expect(WebMock).to have_requested(:post, 'https://api.mixpanel.com/track').
      with { |req| body = req.body }

    message_urlencoded = body[/^data=(.*?)(?:&|$)/, 1]
    message_json = Base64.strict_decode64(CGI.unescape(message_urlencoded))
    message = JSON.load(message_json)
    expect(message).to eq({
        'event' => 'TEST EVENT',
        'properties' => {
            'Circumstances' => 'During test',
            'distinct_id' => 'TEST ID',
            'mp_lib' => 'ruby',
            '$lib_version' => Mixpanel::VERSION,
            'token' => 'TEST TOKEN',
            'time' => @time_now.to_i * 1000
        }
    })
  end

  it 'should call a consumer block if one is given' do
    messages = []
    mixpanel = Mixpanel::Tracker.new('TEST TOKEN') do |type, message|
      messages << [type, JSON.load(message)]
    end
    mixpanel.track('ID', 'Event')
    mixpanel.import('API_KEY', 'ID', 'Import')
    mixpanel.people.set('ID', {'k' => 'v'})
    mixpanel.people.append('ID', {'k' => 'v'})

    expect = [
        [ :event, 'data' =>
          { 'event' => 'Event',
            'properties' => {
              'distinct_id' => 'ID',
              'mp_lib' => 'ruby',
              '$lib_version' => Mixpanel::VERSION,
              'token' => 'TEST TOKEN',
              'time' => @time_now.to_i * 1000
            }
          }
        ],
        [ :import, {
            'data' => {
              'event' => 'Import',
              'properties' => {
                'distinct_id' => 'ID',
                'mp_lib' => 'ruby',
                '$lib_version' => Mixpanel::VERSION,
                'token' => 'TEST TOKEN',
                'time' => @time_now.to_i * 1000
              }
            },
            'api_key' => 'API_KEY',
          }
        ],
        [ :profile_update, 'data' =>
          { '$token' => 'TEST TOKEN',
            '$distinct_id' => 'ID',
            '$time' => @time_now.to_i * 1000,
            '$set' => {'k' => 'v'}
          }
        ],
        [ :profile_update, 'data' =>
          { '$token' => 'TEST TOKEN',
            '$distinct_id' => 'ID',
            '$time' => @time_now.to_i * 1000,
            '$append' => {'k' => 'v'}
          }
        ]
    ]
    expect.zip(messages).each do |expect, found|
      expect(expect).to eq(found)
    end
  end

  describe 'service account credentials' do
    it 'should pass credentials to flags providers when passed directly' do
      credentials = Mixpanel::ServiceAccountCredentials.new('user', 'secret', 'project123')

      tracker = Mixpanel::Tracker.new(
        'TEST TOKEN',
        nil,
        credentials: credentials,
        local_flags_config: {},
        remote_flags_config: {}
      )

      # Verify credentials were passed to providers by checking internal state
      expect(tracker.local_flags.instance_variable_get(:@credentials)).to eq(credentials)
      expect(tracker.remote_flags.instance_variable_get(:@credentials)).to eq(credentials)
    end
  end
end
