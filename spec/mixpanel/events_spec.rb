require 'spec_helper'
require 'mixpanel/events.rb'

describe MixpanelEvents do
  before(:each) do
    pending 'Still to be written'
    @log = LogConsumer.new
    @events = MixpanelEvents.new('TEST TOKEN', { :consumer => @log })
  end

  it 'should send a well formed track/ message' do
    @events.track('TEST ID', 'Test Event', {
                    'Circumstances' => 'During a test'
                  })
    @log.messages.should eq([ 'DUNNO' ])
  end
end
