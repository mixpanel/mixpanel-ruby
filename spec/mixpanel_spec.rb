require 'mixpanel'
require 'base64'
require 'json'
require 'uri'

describe Mixpanel do
  before(:each) do
    WebMock.reset!
    stub_request(:any, 'http://api.mixpanel.com:443/track').to_return({ :body => "1\n" })
    stub_request(:any, 'http://api.mixpanel.com:443/engage').to_return({ :body => "1\n" })
    @mixpanel = Mixpanel.new('TEST TOKEN')
  end

  it 'should send a request to the track api with the default consumer' do
    @mixpanel.track('TEST ID', 'TEST EVENT', { 'Circumstances' => 'During test' })

    body = nil
    WebMock.should have_requested(:post, 'api.mixpanel.com:443/track').with { |req|
      body = req.body
    }

    message_urlencoded = body[/^data=(.*)$/, 1]
    message_json = Base64.strict_decode64(URI.unescape(message_urlencoded))
    message = JSON.load(message_json)
    message.should eq({
        'event' => 'TEST EVENT',
        'properties' => {
            'Circumstances' => 'During test',
            'distinct_id' => 'TEST ID',
            'token' => 'TEST TOKEN',
        }
    })
  end
end
