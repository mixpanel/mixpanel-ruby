require 'mixpanel-ruby'
require 'base64'
require 'json'
require 'uri'

describe Mixpanel::Tracker do
  before(:each) do
    @time_now = Time.parse('Jun 6 1972, 16:23:04')
    Time.stub!(:now).and_return(@time_now)
  end

  it 'should send an alias message to mixpanel no matter what the consumer is' do
    WebMock.reset!
    stub_request(:any, 'https://api.mixpanel.com/track').to_return({ :body => "1" })
    mixpanel = Mixpanel::Tracker.new('TEST TOKEN') {|*args| }
    mixpanel.alias('TEST ALIAS', 'TEST ID')

    WebMock.should have_requested(:post, 'https://api.mixpanel.com/track').
      with(:body => { :data => 'eyJldmVudCI6IiRjcmVhdGVfYWxpYXMiLCJwcm9wZXJ0aWVzIjp7ImRpc3RpbmN0X2lkIjoiVEVTVCBJRCIsImFsaWFzIjoiVEVTVCBBTElBUyIsInRva2VuIjoiVEVTVCBUT0tFTiJ9fQ==' })
  end

  it 'should send a request to the track api with the default consumer' do
    WebMock.reset!
    stub_request(:any, 'https://api.mixpanel.com/track').to_return({ :body => "1" })
    stub_request(:any, 'https://api.mixpanel.com/engage').to_return({ :body => "1" })
    mixpanel = Mixpanel::Tracker.new('TEST TOKEN')

    mixpanel.track('TEST ID', 'TEST EVENT', { 'Circumstances' => 'During test' })

    body = nil
    WebMock.should have_requested(:post, 'https://api.mixpanel.com/track').
      with { |req| body = req.body }

    message_urlencoded = body[/^data=(.*)$/, 1]
    message_json = Base64.strict_decode64(URI.unescape(message_urlencoded))
    message = JSON.load(message_json)
    message.should eq({
        'event' => 'TEST EVENT',
        'properties' => {
            'Circumstances' => 'During test',
            'distinct_id' => 'TEST ID',
            'mp_lib' => 'ruby',
            '$lib_version' => Mixpanel::VERSION,
            'token' => 'TEST TOKEN',
            'time' => @time_now.to_i
        }
    })
  end

  it 'should call a consumer block if one is given' do
    messages = []
    mixpanel = Mixpanel::Tracker.new('TEST TOKEN') do |type, message|
      messages << [ type, JSON.load(message['data']) ]
    end
    mixpanel.track('ID', 'Event')
    mixpanel.people.set('ID', { 'k' => 'v' })
    mixpanel.people.append('ID', { 'k' => 'v' })

    messages.should eq([
        [ :event,
          { 'event' => 'Event',
            'properties' => {
              'distinct_id' => 'ID',
              'mp_lib' => 'ruby',
              '$lib_version' => Mixpanel::VERSION,
              'token' => 'TEST TOKEN',
              'time' => @time_now.to_i
            }
          }
        ],
        [ :profile_update,
          { '$token' => 'TEST TOKEN',
            '$distinct_id' => 'ID',
            '$time' => @time_now.to_i * 1000,
            '$set' => { 'k' => 'v' }
          }
        ],
        [ :profile_update,
          { '$token' => 'TEST TOKEN',
            '$distinct_id' => 'ID',
            '$time' => @time_now.to_i * 1000,
            '$append' => { 'k' => 'v' }
          }
        ]
    ])
  end
end
