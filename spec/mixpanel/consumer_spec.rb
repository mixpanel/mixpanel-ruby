require 'spec_helper'
require 'webmock'
require 'base64'
require 'mixpanel/consumer'

describe MixpanelConsumer do
  before(:each) do
    WebMock.reset!
    stub_request(:any, 'http://api.mixpanel.com:443/track').to_return({ :body => "1\n" })
    stub_request(:any, 'http://api.mixpanel.com:443/engage').to_return({ :body => "1\n" })
    @consumer = MixpanelConsumer.new
  end

  it 'should send a request to api.mixpanel.com/track on events' do
    @consumer.send_event('TEST EVENT MESSAGE')
    WebMock.should have_requested(:post, 'api.mixpanel.com:443/track').
      with(:body => {'data' => 'VEVTVCBFVkVOVCBNRVNTQUdF' })
  end

  it 'should send a request to api.mixpanel.com/people on profile updates' do
    @consumer.send_profile_update('TEST EVENT MESSAGE')
    WebMock.should have_requested(:post, 'api.mixpanel.com:443/engage').
      with(:body => {'data' => 'VEVTVCBFVkVOVCBNRVNTQUdF' })
  end
end
