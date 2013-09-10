require 'spec_helper'
require 'webmock'
require 'base64'
require 'mixpanel-ruby/consumer'

describe "Mixpanel backward compatibility" do
  before(:each) do
    WebMock.reset!
    @consumer = Mixpanel::Consumer.new
    stub_request(:any, 'https://api.mixpanel.com/track').to_return({ :body => "1" })
    @message = 'BASE64-ENCODED VERSION OF BIN. THIS METHOD COMPLIES WITH RFC 2045. LINE FEEDS ARE ADDED TO EVERY 60 ENCODED CHARACTORS. IN RUBY 1.8 WE NEED TO JUST CALL ENCODE64 AND REMOVE THE LINE FEEDS, IN RUBY 1.9 WE CALL STRIC_ENCODED64 METHOD INSTEAD'
    @base64_msg = "IkJBU0U2NC1FTkNPREVEIFZFUlNJT04gT0YgQklOLiBUSElTIE1FVEhPRCBDT01QTElFUyBXSVRIIFJGQyAyMDQ1LiBMSU5FIEZFRURTIEFSRSBBRERFRCBUTyBFVkVSWSA2MCBFTkNPREVEIENIQVJBQ1RPUlMuIElOIFJVQlkgMS44IFdFIE5FRUQgVE8gSlVTVCBDQUxMIEVOQ09ERTY0IEFORCBSRU1PVkUgVEhFIExJTkUgRkVFRFMsIElOIFJVQlkgMS45IFdFIENBTEwgU1RSSUNfRU5DT0RFRDY0IE1FVEhPRCBJTlNURUFEIg=="
  end

  it 'should encode the message in base64 without new lines in MRI 1.8' do
    stub_const("RUBY_VERSION", "1.8.7")
    @consumer.send(:event, { 'data' => @message }.to_json)
    WebMock.should have_requested(:post, 'https://api.mixpanel.com/track').
      with(:body => { 'data' => @base64_msg })
  end

  it 'should encode the message in base64 without new lines in MRI 1.9' do
    stub_const("RUBY_VERSION", "1.9.3")
    @consumer.send(:event, { 'data' => @message }.to_json)
    WebMock.should have_requested(:post, 'https://api.mixpanel.com/track').
      with(:body => { 'data' => @base64_msg })
  end
end