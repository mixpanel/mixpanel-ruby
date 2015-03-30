require 'mixpanel-ruby'
require 'base64'
require 'json'
require 'uri'

describe Mixpanel::Tracker do
  before(:each) do
    @time_now = Time.parse('Jun 6 1972, 16:23:04')
    allow(Time).to receive(:now).and_return(@time_now)
  end

  it 'should send an alias message to mixpanel no matter what the consumer is' do
    WebMock.reset!
    stub_request(:any, 'https://api.mixpanel.com/track').to_return({:body => '{"status": 1, "error": null}'})
    mixpanel = Mixpanel::Tracker.new('TEST TOKEN') {|*args| }
    mixpanel.alias('TEST ALIAS', 'TEST ID')

    expect(WebMock).to have_requested(:post, 'https://api.mixpanel.com/track').
      with(:body => {:data => 'eyJldmVudCI6IiRjcmVhdGVfYWxpYXMiLCJwcm9wZXJ0aWVzIjp7ImRpc3RpbmN0X2lkIjoiVEVTVCBJRCIsImFsaWFzIjoiVEVTVCBBTElBUyIsInRva2VuIjoiVEVTVCBUT0tFTiJ9fQ==', 'verbose' => '1'})
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
    message_json = Base64.strict_decode64(URI.unescape(message_urlencoded))
    message = JSON.load(message_json)
    expect(message).to eq({
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

  it 'should return a tracking uri if asked and not execute any requests' do
    mixpanel = Mixpanel::Tracker.new('TEST TOKEN')
    stub_request(:any, 'https://api.mixpanel.com/track').to_return({:body => '{"status": 1, "error": null}'})


    a = mixpanel.track('TEST ID', 'TEST EVENT', {'Circumstances' => 'During test'}, nil, true)
    a.should eq "https://api.mixpanel.com/track?data=eyJldmVudCI6IlRFU1QgRVZFTlQiLCJwcm9wZXJ0aWVzIjp7ImRpc3RpbmN0X2lkIjoiVEVTVCBJRCIsInRva2VuIjoiVEVTVCBUT0tFTiIsInRpbWUiOjc2NzIwOTg0LCJtcF9saWIiOiJydWJ5IiwiJGxpYl92ZXJzaW9uIjoiMS40LjAiLCJDaXJjdW1zdGFuY2VzIjoiRHVyaW5nIHRlc3QifX0%3D&verbose=1&img=1"

    WebMock.should_not have_requested(:post, 'https://api.mixpanel.com/track')
    WebMock.should_not have_requested(:get, 'https://api.mixpanel.com/track')
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
              'time' => @time_now.to_i
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
                'time' => @time_now.to_i
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
end
