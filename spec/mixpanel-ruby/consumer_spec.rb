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
    @consumer.send(:event, {'data' => 'TEST EVENT MESSAGE'}.to_json)
    WebMock.should have_requested(:post, 'https://api.mixpanel.com/track').
      with(:body => {'data' => 'IlRFU1QgRVZFTlQgTUVTU0FHRSI=' })
  end

  it 'should send a request to api.mixpanel.com/people on profile updates' do
    stub_request(:any, 'https://api.mixpanel.com/engage').to_return({ :body => "1" })
    @consumer.send(:profile_update, {'data' => 'TEST EVENT MESSAGE'}.to_json)
    WebMock.should have_requested(:post, 'https://api.mixpanel.com/engage').
      with(:body => {'data' => 'IlRFU1QgRVZFTlQgTUVTU0FHRSI=' })
  end

  it 'should send a request to api.mixpanel.com/import on event imports' do
    stub_request(:any, 'https://api.mixpanel.com/import').to_return({ :body => "1" })
    @consumer.send(:import, {'data' => 'TEST EVENT MESSAGE', 'api_key' => 'API_KEY'}.to_json)
    WebMock.should have_requested(:post, 'https://api.mixpanel.com/import').
      with(:body => {'data' => 'IlRFU1QgRVZFTlQgTUVTU0FHRSI=', 'api_key' => 'API_KEY' })
  end

  it 'should encode long messages without newlines' do
    stub_request(:any, 'https://api.mixpanel.com/track').to_return({ :body => "1" })
    @consumer.send(:event, { 'data' => 'BASE64-ENCODED VERSION OF BIN. THIS METHOD COMPLIES WITH RFC 2045. LINE FEEDS ARE ADDED TO EVERY 60 ENCODED CHARACTORS. IN RUBY 1.8 WE NEED TO JUST CALL ENCODE64 AND REMOVE THE LINE FEEDS, IN RUBY 1.9 WE CALL STRIC_ENCODED64 METHOD INSTEAD' }.to_json)
    WebMock.should have_requested(:post, 'https://api.mixpanel.com/track').
      with(:body => { 'data' => 'IkJBU0U2NC1FTkNPREVEIFZFUlNJT04gT0YgQklOLiBUSElTIE1FVEhPRCBDT01QTElFUyBXSVRIIFJGQyAyMDQ1LiBMSU5FIEZFRURTIEFSRSBBRERFRCBUTyBFVkVSWSA2MCBFTkNPREVEIENIQVJBQ1RPUlMuIElOIFJVQlkgMS44IFdFIE5FRUQgVE8gSlVTVCBDQUxMIEVOQ09ERTY0IEFORCBSRU1PVkUgVEhFIExJTkUgRkVFRFMsIElOIFJVQlkgMS45IFdFIENBTEwgU1RSSUNfRU5DT0RFRDY0IE1FVEhPRCBJTlNURUFEIg==' })
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
    @consumer.send(:event, {'data' => 'TEST EVENT 1'}.to_json)
    WebMock.should have_not_requested(:post, 'https://api.mixpanel.com/track')

    @consumer.flush()
    WebMock.should have_requested(:post, 'https://api.mixpanel.com/track').
      with(:body => {'data' => 'WyJURVNUIEVWRU5UIDEiXQ==' })
  end

  it 'should send one message when max_length events are tracked' do
    stub_request(:any, 'https://api.mixpanel.com/track').to_return({ :body => "1" })

    @max_length.times do |i|
      @consumer.send(:event, {'data' => "x #{i}"}.to_json)
    end

    WebMock.should have_requested(:post, 'https://api.mixpanel.com/track').
      with(:body => {'data' => 'WyJ4IDAiLCJ4IDEiLCJ4IDIiLCJ4IDMiLCJ4IDQiLCJ4IDUiLCJ4IDYiLCJ4IDciLCJ4IDgiLCJ4IDkiXQ==' })
  end

  it 'should send one message per api key on import' do
    stub_request(:any, 'https://api.mixpanel.com/import').to_return({ :body => "1" })
    @consumer.send(:import, {'data' => 'TEST EVENT 1', 'api_key' => 'KEY 1'}.to_json)
    @consumer.send(:import, {'data' => 'TEST EVENT 1', 'api_key' => 'KEY 2'}.to_json)
    @consumer.send(:import, {'data' => 'TEST EVENT 2', 'api_key' => 'KEY 1'}.to_json)
    @consumer.send(:import, {'data' => 'TEST EVENT 2', 'api_key' => 'KEY 2'}.to_json)
    @consumer.flush

    WebMock.should have_requested(:post, 'https://api.mixpanel.com/import').
      with(:body => {'data' => 'IlRFU1QgRVZFTlQgMSI=', 'api_key' => 'KEY 1' })

    WebMock.should have_requested(:post, 'https://api.mixpanel.com/import').
      with(:body => {'data' => 'IlRFU1QgRVZFTlQgMSI=', 'api_key' => 'KEY 2' })
  end
end
