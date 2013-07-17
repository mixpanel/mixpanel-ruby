require 'spec_helper'
require 'webmock'
require 'base64'
require 'mixpanel-ruby/consumer'

describe Mixpanel::Consumer do
  before(:each) do
    WebMock.reset!
    @consumer = Mixpanel::Consumer.new
  end

  it 'should send a request to api.mixpanel.com/track on events' do
    stub_request(:any, 'https://api.mixpanel.com/track').to_return({ :body => "1" })
    @consumer.send(:event, 'data' => 'TEST EVENT MESSAGE')
    WebMock.should have_requested(:post, 'https://api.mixpanel.com/track').
      with(:body => {'data' => 'VEVTVCBFVkVOVCBNRVNTQUdF' })
  end

  it 'should send a request to api.mixpanel.com/people on profile updates' do
    stub_request(:any, 'https://api.mixpanel.com/engage').to_return({ :body => "1" })
    @consumer.send(:profile_update, 'data' => 'TEST EVENT MESSAGE')
    WebMock.should have_requested(:post, 'https://api.mixpanel.com/engage').
      with(:body => {'data' => 'VEVTVCBFVkVOVCBNRVNTQUdF' })
  end

  it 'should send a request to api.mixpanel.com/import on event imports' do
    stub_request(:any, 'https://api.mixpanel.com/import').to_return({ :body => "1" })
    @consumer.send(:import, 'data' => 'TEST EVENT MESSAGE', 'api_key' => 'API_KEY')
    WebMock.should have_requested(:post, 'https://api.mixpanel.com/import').
      with(:body => {'data' => 'VEVTVCBFVkVOVCBNRVNTQUdF', 'api_key' => 'API_KEY' })
  end
end

describe Mixpanel::BufferedConsumer do
  before(:each) do
    WebMock.reset!
    @max_length = 10
    @consumer = Mixpanel::BufferedConsumer.new(nil, nil, nil, @max_length)
  end

  it 'should not send a request for a single message until flush is called' do
    stub_request(:any, 'https://api.mixpanel.com/track').to_return({ :body => "1" })
    @consumer.send(:event, 'data' => 'TEST EVENT 1')
    WebMock.should have_not_requested(:post, 'https://api.mixpanel.com/track')

    @consumer.flush()
    WebMock.should have_requested(:post, 'https://api.mixpanel.com/track').
      with(:body => {'data' => 'WyBURVNUIEVWRU5UIDEgXQ==' })
  end

  it 'should send one message when max_length events are tracked' do
    stub_request(:any, 'https://api.mixpanel.com/track').to_return({ :body => "1" })

    @max_length.times do |i|
      @consumer.send(:event, 'data' => "x #{i}")
    end

    WebMock.should have_requested(:post, 'https://api.mixpanel.com/track').
      with(:body => {'data' => 'WyB4IDAseCAxLHggMix4IDMseCA0LHggNSx4IDYseCA3LHggOCx4IDkgXQ==' })
  end
end
