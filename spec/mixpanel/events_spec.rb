require 'spec_helper'
require 'mixpanel/events.rb'

describe MixpanelEvents do
  before(:each) do
    @log = LogConsumer.new
    @events = MixpanelEvents.new('TEST TOKEN', { :consumer => @log })
  end

  it 'should send a well formed track/ message' do
    @events.track('TEST ID', 'Test Event', {
        'Circumstances' => 'During a test'
    })
    @log.messages.should eq([['EVENTS', {
        'event' => 'Test Event',
        'properties' => {
            'Circumstances' => 'During a test',
            'distinct_id' => 'TEST ID',
            'token' => 'TEST TOKEN'
        }
    }]])
  end
end
