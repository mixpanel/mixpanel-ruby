require 'base64'
require 'spec_helper'
require 'webmock'

require 'mixpanel-ruby/consumer'
require 'mixpanel-ruby/credentials'

describe Mixpanel::Consumer do
  before { WebMock.reset! }

  shared_examples_for 'consumer' do
    it 'should send a request to api.mixpanel.com/track on events' do
      stub_request(:any, 'https://api.mixpanel.com/track').to_return({:body => '{"status": 1, "error": null}'})
      subject.send!(:event, {'data' => 'TEST EVENT MESSAGE'}.to_json)
      expect(WebMock).to have_requested(:post, 'https://api.mixpanel.com/track').
        with(:body => {'data' => 'IlRFU1QgRVZFTlQgTUVTU0FHRSI=', 'verbose' => '1' })
    end

    it 'should send a request to api.mixpanel.com/people on profile updates' do
      stub_request(:any, 'https://api.mixpanel.com/engage').to_return({:body => '{"status": 1, "error": null}'})
      subject.send!(:profile_update, {'data' => 'TEST EVENT MESSAGE'}.to_json)
      expect(WebMock).to have_requested(:post, 'https://api.mixpanel.com/engage').
        with(:body => {'data' => 'IlRFU1QgRVZFTlQgTUVTU0FHRSI=', 'verbose' => '1' })
    end

    it 'should send a request to api.mixpanel.com/groups on groups updates' do
      stub_request(:any, 'https://api.mixpanel.com/groups').to_return({:body => '{"status": 1, "error": null}'})
      subject.send!(:group_update, {'data' => 'TEST EVENT MESSAGE'}.to_json)
      expect(WebMock).to have_requested(:post, 'https://api.mixpanel.com/groups').
        with(:body => {'data' => 'IlRFU1QgRVZFTlQgTUVTU0FHRSI=', 'verbose' => '1' })
    end

    it 'should send a request to api.mixpanel.com/import on event imports' do
      stub_request(:any, 'https://api.mixpanel.com/import').to_return({:body => '{"status": 1, "error": null}'})
      subject.send!(:import, {'data' => 'TEST EVENT MESSAGE', 'api_key' => 'API_KEY','verbose' => '1' }.to_json)
      expect(WebMock).to have_requested(:post, 'https://api.mixpanel.com/import').
        with(:body => {'data' => 'IlRFU1QgRVZFTlQgTUVTU0FHRSI=', 'api_key' => 'API_KEY', 'verbose' => '1' })
    end

    it 'should encode long messages without newlines' do
      stub_request(:any, 'https://api.mixpanel.com/track').to_return({:body => '{"status": 1, "error": null}'})
      subject.send!(:event, {'data' => 'BASE64-ENCODED VERSION OF BIN. THIS METHOD COMPLIES WITH RFC 2045. LINE FEEDS ARE ADDED TO EVERY 60 ENCODED CHARACTORS. IN RUBY 1.8 WE NEED TO JUST CALL ENCODE64 AND REMOVE THE LINE FEEDS, IN RUBY 1.9 WE CALL STRIC_ENCODED64 METHOD INSTEAD'}.to_json)
      expect(WebMock).to have_requested(:post, 'https://api.mixpanel.com/track').
        with(:body => {'data' => 'IkJBU0U2NC1FTkNPREVEIFZFUlNJT04gT0YgQklOLiBUSElTIE1FVEhPRCBDT01QTElFUyBXSVRIIFJGQyAyMDQ1LiBMSU5FIEZFRURTIEFSRSBBRERFRCBUTyBFVkVSWSA2MCBFTkNPREVEIENIQVJBQ1RPUlMuIElOIFJVQlkgMS44IFdFIE5FRUQgVE8gSlVTVCBDQUxMIEVOQ09ERTY0IEFORCBSRU1PVkUgVEhFIExJTkUgRkVFRFMsIElOIFJVQlkgMS45IFdFIENBTEwgU1RSSUNfRU5DT0RFRDY0IE1FVEhPRCBJTlNURUFEIg==', 'verbose' => '1'})
    end

    it 'should provide thorough information in case mixpanel fails' do
      stub_request(:any, 'https://api.mixpanel.com/track').to_return({:status => 401, :body => "nutcakes"})
      expect { subject.send!(:event, {'data' => 'TEST EVENT MESSAGE'}.to_json) }.to raise_exception('Could not write to Mixpanel, server responded with 401 returning: \'nutcakes\'')
    end

    it 'should still respond to send' do
      stub_request(:any, 'https://api.mixpanel.com/track').to_return({:body => '{"status": 1, "error": null}'})
      subject.send(:event, {'data' => 'TEST EVENT MESSAGE'}.to_json)
      expect(WebMock).to have_requested(:post, 'https://api.mixpanel.com/track').
        with(:body => {'data' => 'IlRFU1QgRVZFTlQgTUVTU0FHRSI=', 'verbose' => '1' })
    end

    it 'should raise server error if response body is empty' do
      stub_request(:any, 'https://api.mixpanel.com/track').to_return({:body => ''})
      expect { subject.send!(:event, {'data' => 'TEST EVENT MESSAGE'}.to_json) }.to raise_exception(Mixpanel::ServerError, /Could not interpret Mixpanel server response: ''/)
      expect(WebMock).to have_requested(:post, 'https://api.mixpanel.com/track').
        with(:body => {'data' => 'IlRFU1QgRVZFTlQgTUVTU0FHRSI=', 'verbose' => '1' })
    end

    it 'should raise server error when verbose is disabled', :skip => true do
      stub_request(:any, 'https://api.mixpanel.com/track').to_return({:body => '0'})
      expect { subject.send!(:event, {'data' => 'TEST EVENT MESSAGE'}.to_json) }.to raise_exception(Mixpanel::ServerError, /Could not interpret Mixpanel server response: '0'/)
      expect(WebMock).to have_requested(:post, 'https://api.mixpanel.com/track').
        with(:body => {'data' => 'IlRFU1QgRVZFTlQgTUVTU0FHRSI=', 'verbose' => '1' })
    end
  end

  context 'raw consumer' do
    it_behaves_like 'consumer'
  end

  context 'custom request consumer' do
    subject do
      ret = Mixpanel::Consumer.new
      class << ret
        attr_reader :called
        def request(*args)
          @called = true
          super(*args)
        end
      end

      ret
    end

    after(:each) do
      expect(subject.called).to be_truthy
    end

    it_behaves_like 'consumer'
  end

  context 'service account credentials' do
    it 'should send a request to api.mixpanel.com/import with service account credentials' do
      stub_request(:any, 'https://api.mixpanel.com/import?project_id=test-project-123').to_return({:body => '{"status": 1, "error": null}'})
      credentials = Mixpanel::ServiceAccountCredentials.new('test-user', 'test-secret', 'test-project-123')
      consumer = Mixpanel::Consumer.new(nil, nil, nil, nil, credentials: credentials)

      consumer.send!(:import, {'data' => 'TEST EVENT MESSAGE'}.to_json)

      # Should use Basic Auth header with username:secret
      # Should add project_id as query parameter
      # Should NOT include credentials in POST body or message
      expect(WebMock).to have_requested(:post, 'https://api.mixpanel.com/import?project_id=test-project-123').
        with(
          :body => {
            'data' => 'IlRFU1QgRVZFTlQgTUVTU0FHRSI=',
            'verbose' => '1'
          },
          :headers => {
            'Authorization' => 'Basic ' + Base64.strict_encode64('test-user:test-secret')
          }
        )
    end

    it 'should accept credentials as a hash with string keys' do
      stub_request(:any, 'https://api.mixpanel.com/import?project_id=proj-456').to_return({:body => '{"status": 1, "error": null}'})
      consumer = Mixpanel::Consumer.new

      credentials_hash = {'username' => 'hash-user', 'secret' => 'hash-secret', 'project_id' => 'proj-456'}
      # Directly call request with credentials hash to test hash handling
      consumer.request('https://api.mixpanel.com/import', {'data' => 'test', 'verbose' => '1'}, credentials: credentials_hash, type: :import)

      expect(WebMock).to have_requested(:post, 'https://api.mixpanel.com/import?project_id=proj-456').
        with(
          :headers => {
            'Authorization' => 'Basic ' + Base64.strict_encode64('hash-user:hash-secret')
          }
        )
    end

    it 'should accept credentials as a hash with symbol keys' do
      stub_request(:any, 'https://api.mixpanel.com/import?project_id=proj-789').to_return({:body => '{"status": 1, "error": null}'})
      consumer = Mixpanel::Consumer.new

      credentials_hash = {username: 'sym-user', secret: 'sym-secret', project_id: 'proj-789'}
      consumer.request('https://api.mixpanel.com/import', {'data' => 'test', 'verbose' => '1'}, credentials: credentials_hash, type: :import)

      expect(WebMock).to have_requested(:post, 'https://api.mixpanel.com/import?project_id=proj-789').
        with(
          :headers => {
            'Authorization' => 'Basic ' + Base64.strict_encode64('sym-user:sym-secret')
          }
        )
    end

    it 'should raise ArgumentError when credentials hash is missing username' do
      consumer = Mixpanel::Consumer.new
      credentials_hash = {secret: 'secret', project_id: 'proj'}

      expect {
        consumer.request('https://api.mixpanel.com/import', {'data' => 'test', 'verbose' => '1'}, credentials: credentials_hash, type: :import)
      }.to raise_error(ArgumentError, "credentials hash missing 'username'")
    end

    it 'should raise ArgumentError when credentials hash is missing secret' do
      consumer = Mixpanel::Consumer.new
      credentials_hash = {username: 'user', project_id: 'proj'}

      expect {
        consumer.request('https://api.mixpanel.com/import', {'data' => 'test', 'verbose' => '1'}, credentials: credentials_hash, type: :import)
      }.to raise_error(ArgumentError, "credentials hash missing 'secret'")
    end

    it 'should raise ArgumentError when credentials hash is missing project_id' do
      consumer = Mixpanel::Consumer.new
      credentials_hash = {username: 'user', secret: 'secret'}

      expect {
        consumer.request('https://api.mixpanel.com/import', {'data' => 'test', 'verbose' => '1'}, credentials: credentials_hash, type: :import)
      }.to raise_error(ArgumentError, "credentials hash missing 'project_id'")
    end

    it 'should raise ArgumentError when credentials is not ServiceAccountCredentials or Hash' do
      consumer = Mixpanel::Consumer.new

      expect {
        consumer.request('https://api.mixpanel.com/import', {'data' => 'test', 'verbose' => '1'}, credentials: 'invalid', type: :import)
      }.to raise_error(ArgumentError, /credentials must be ServiceAccountCredentials or Hash, got String/)
    end

    it 'should not include api_key when credentials are present' do
      stub_request(:any, 'https://api.mixpanel.com/import?project_id=test-project').to_return({:body => '{"status": 1, "error": null}'})
      credentials = Mixpanel::ServiceAccountCredentials.new('user', 'secret', 'test-project')
      consumer = Mixpanel::Consumer.new(nil, nil, nil, nil, credentials: credentials)

      # Message includes api_key but it should be ignored when credentials are present
      consumer.send!(:import, {'data' => 'TEST EVENT MESSAGE', 'api_key' => 'SHOULD_BE_IGNORED'}.to_json)

      # api_key should NOT be in the request body (only data and verbose)
      expect(WebMock).to have_requested(:post, 'https://api.mixpanel.com/import?project_id=test-project').
        with(
          :body => {
            'data' => 'IlRFU1QgRVZFTlQgTUVTU0FHRSI=',
            'verbose' => '1'
          }
        )
    end
  end

end

describe Mixpanel::BufferedConsumer do
  let(:max_length) { 10 }
  before { WebMock.reset! }

  context 'Default BufferedConsumer' do
    subject { Mixpanel::BufferedConsumer.new(nil, nil, nil, max_length) }

    it 'should not send a request for a single message until flush is called' do
      stub_request(:any, 'https://api.mixpanel.com/track').to_return({:body => '{"status": 1, "error": null}'})
      subject.send!(:event, {'data' => 'TEST EVENT 1'}.to_json)
      expect(WebMock).to have_not_requested(:post, 'https://api.mixpanel.com/track')

      subject.flush()
      expect(WebMock).to have_requested(:post, 'https://api.mixpanel.com/track').
        with(:body => {'data' => 'WyJURVNUIEVWRU5UIDEiXQ==', 'verbose' => '1' })
    end

    it 'should still respond to send' do
      stub_request(:any, 'https://api.mixpanel.com/track').to_return({:body => '{"status": 1, "error": null}'})
      subject.send(:event, {'data' => 'TEST EVENT 1'}.to_json)
      expect(WebMock).to have_not_requested(:post, 'https://api.mixpanel.com/track')
    end

    it 'should send one message when max_length events are tracked' do
      stub_request(:any, 'https://api.mixpanel.com/track').to_return({:body => '{"status": 1, "error": null}'})

      max_length.times do |i|
        subject.send!(:event, {'data' => "x #{i}"}.to_json)
      end

      expect(WebMock).to have_requested(:post, 'https://api.mixpanel.com/track').
        with(:body => {'data' => 'WyJ4IDAiLCJ4IDEiLCJ4IDIiLCJ4IDMiLCJ4IDQiLCJ4IDUiLCJ4IDYiLCJ4IDciLCJ4IDgiLCJ4IDkiXQ==', 'verbose' => '1' })
    end

    it 'should send one message per api key on import' do
      stub_request(:any, 'https://api.mixpanel.com/import').to_return({:body => '{"status": 1, "error": null}'})
      subject.send!(:import, {'data' => 'TEST EVENT 1', 'api_key' => 'KEY 1'}.to_json)
      subject.send!(:import, {'data' => 'TEST EVENT 1', 'api_key' => 'KEY 2'}.to_json)
      subject.send!(:import, {'data' => 'TEST EVENT 2', 'api_key' => 'KEY 1'}.to_json)
      subject.send!(:import, {'data' => 'TEST EVENT 2', 'api_key' => 'KEY 2'}.to_json)
      subject.flush

      expect(WebMock).to have_requested(:post, 'https://api.mixpanel.com/import').
        with(:body => {'data' => 'IlRFU1QgRVZFTlQgMSI=', 'api_key' => 'KEY 1', 'verbose' => '1' })

      expect(WebMock).to have_requested(:post, 'https://api.mixpanel.com/import').
        with(:body => {'data' => 'IlRFU1QgRVZFTlQgMSI=', 'api_key' => 'KEY 2', 'verbose' => '1' })
    end
  end

  context 'BufferedConsumer with block' do
    let(:messages_seen) { [] }
    subject do
      Mixpanel::BufferedConsumer.new(nil, nil, nil, 3) do |type, message|
        messages_seen << [type, message]
      end
    end

    it 'should call block instead of making default requests on flush' do
      3.times do |i|
        subject.send!(:event, {'data' => "x #{i}"}.to_json)
      end

      expect(messages_seen).to match_array(
        [[:event, "{\"data\":[\"x 0\",\"x 1\",\"x 2\"]}"]]
      )
    end

  end

  context 'with failing requests' do
    let(:sent_messages) { [] }
    let(:submission_queue) { [] }
    subject do
      Mixpanel::BufferedConsumer.new(nil, nil, nil, 2) do |type, message|
        raise Mixpanel::ServerError if submission_queue.shift == :fail
        sent_messages << [type, message]
      end
    end

    it 'clears any slices that complete on flush' do
      # construct a consumer that is backed up and has a multi-slice buffer
      3.times { submission_queue << :fail }
      4.times do |i|
        begin
          subject.send!(:event, {'data' => i}.to_json)
        rescue Mixpanel::ServerError
        end
      end
      expect(sent_messages).to match_array([])

      submission_queue << :pass
      submission_queue << :fail

      expect { subject.flush }.to raise_error Mixpanel::ServerError
      expect(sent_messages).to match_array([
        [:event, '{"data":[0,1]}']
      ])

      submission_queue << :pass
      subject.flush
      expect(sent_messages).to match_array([
        [:event, '{"data":[0,1]}'],
        [:event, '{"data":[2,3]}'],
      ])
    end
  end

  context 'with service account credentials' do
    it 'should pass credentials to consumer when using BufferedConsumer' do
      stub_request(:any, 'https://api.mixpanel.com/import?project_id=buffered-project').to_return({:body => '{"status": 1, "error": null}'})
      credentials = Mixpanel::ServiceAccountCredentials.new('buffered-user', 'buffered-secret', 'buffered-project')
      consumer = Mixpanel::BufferedConsumer.new(nil, nil, nil, 2, credentials: credentials)

      # Import messages are not buffered - they're sent immediately
      consumer.send!(:import, {'data' => 'EVENT 1'}.to_json)

      # Verify credentials were used in the request
      expect(WebMock).to have_requested(:post, 'https://api.mixpanel.com/import?project_id=buffered-project').
        with(
          :headers => {
            'Authorization' => 'Basic ' + Base64.strict_encode64('buffered-user:buffered-secret')
          }
        ).once
    end
  end

end

describe 'Connection error handling' do
  it 'should raise ConnectionError when network error occurs' do
    stub_request(:any, 'https://api.mixpanel.com/track').to_raise(StandardError.new('Network timeout'))
    consumer = Mixpanel::Consumer.new

    expect {
      consumer.send!(:event, {'data' => 'TEST EVENT MESSAGE'}.to_json)
    }.to raise_error(Mixpanel::ConnectionError, /Could not connect to Mixpanel, with error "Network timeout"/)
  end
end
