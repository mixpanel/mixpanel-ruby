require 'spec_helper'
require 'time'

require 'mixpanel-ruby/events.rb'
require 'mixpanel-ruby/version.rb'

describe Mixpanel::Events do
  before(:each) do
    @time_now = Time.parse('Jun 6 1972, 16:23:04')
    allow(Time).to receive(:now).and_return(@time_now)

    @log = []
    @events = Mixpanel::Events.new('TEST TOKEN') do |type, message|
      @log << [type, JSON.load(message)]
    end
  end

  it 'should send a well formed track/ message' do
    @events.track('TEST ID', 'Test Event', {
        'Circumstances' => 'During a test'
    })
    expect(@log).to eq([[:event, 'data' => {
        'event' => 'Test Event',
        'properties' => {
            'Circumstances' => 'During a test',
            'distinct_id' => 'TEST ID',
            'mp_lib' => 'ruby',
            '$lib_version' => Mixpanel::VERSION,
            'token' => 'TEST TOKEN',
            'time' => @time_now.to_i
        }
    }]])
  end

  it 'should send a well formed import/ message' do
    @events.import('API_KEY', 'TEST ID', 'Test Event', {
        'Circumstances' => 'During a test'
    })
    expect(@log).to eq([[:import, {
        'api_key' => 'API_KEY',
        'data' => {
            'event' => 'Test Event',
            'properties' => {
                'Circumstances' => 'During a test',
                'distinct_id' => 'TEST ID',
                'mp_lib' => 'ruby',
                '$lib_version' => Mixpanel::VERSION,
                'token' => 'TEST TOKEN',
                'time' => @time_now.to_i
            }
        }
    } ]])
  end

  it 'should allow users to pass timestamp for import' do
    older_time = Time.parse('Jun 6 1971, 16:23:04')
    @events.import('API_KEY', 'TEST ID', 'Test Event', {
        'Circumstances' => 'During a test',
        'time' => older_time.to_i,
    })
    expect(@log).to eq([[:import, {
        'api_key' => 'API_KEY',
        'data' => {
            'event' => 'Test Event',
            'properties' => {
                'Circumstances' => 'During a test',
                'distinct_id' => 'TEST ID',
                'mp_lib' => 'ruby',
                '$lib_version' => Mixpanel::VERSION,
                'token' => 'TEST TOKEN',
                'time' => older_time.to_i,
            }
        }
    } ]])
  end
end
