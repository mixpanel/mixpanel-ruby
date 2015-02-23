require 'spec_helper'
require 'mixpanel-ruby/events.rb'
require 'mixpanel-ruby/version.rb'
require 'time'

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

  it 'should send a well formed batch track/ message' do
    events = [
      { 'Test Event' => {
          'Circumstances' => 'During a test'
      }},
      { 'Other Event' => {
          'Circumstances' => 'During a different test'
      }},
      "Event Without Properties"
    ]
    @events.track_batch('TEST ID', events)

    expect(@log).to eq([[:event, 'data' => [
      {
        'event' => 'Test Event',
        'properties' => {
            'distinct_id' => 'TEST ID',
            'token' => 'TEST TOKEN',
            'time' => @time_now.to_i,
            'mp_lib' => 'ruby',
            '$lib_version' => Mixpanel::VERSION,
            'Circumstances' => 'During a test',
        }
      },
      {
        'event' => 'Other Event',
        'properties' => {
            'distinct_id' => 'TEST ID',
            'token' => 'TEST TOKEN',
            'time' => @time_now.to_i,
            'mp_lib' => 'ruby',
            '$lib_version' => Mixpanel::VERSION,
            'Circumstances' => 'During a different test',
        }
      },
      {
        'event' => 'Event Without Properties',
        'properties' => {
            'distinct_id' => 'TEST ID',
            'token' => 'TEST TOKEN',
            'time' => @time_now.to_i,
            'mp_lib' => 'ruby',
            '$lib_version' => Mixpanel::VERSION
        }
      }
    ]]])
  end

  it 'should send track/ messages in batches of 50' do
    events = Array.new(75, "Some Event")
    batches = 75.times.map do |i|
      {
        'event' => 'Some Event',
        'properties' => {
            'distinct_id' => 'TEST ID',
            'token' => 'TEST TOKEN',
            'time' => @time_now.to_i,
            'mp_lib' => 'ruby',
            '$lib_version' => Mixpanel::VERSION
        }
      }
    end

    @events.track_batch('TEST ID', events)
    expect(@log).to eq([
      [:event, { 'data' => batches[0, 50] }],
      [:event, { 'data' => batches[50, 25] }]
    ])
  end

end

