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
            'time' => @time_now.to_i * 1000
        }
    }]])
  end

  it 'should send a well formed import/ message with service account credentials' do
    @events.import(
      { service_account_username: 'sa@serviceaccount.mixpanel.com',
        service_account_password: 'sa-secret',
        project_id: '12345' },
      'TEST ID', 'Test Event', { 'Circumstances' => 'During a test' }
    )
    expect(@log).to eq([[:import, {
        'credentials' => {
            'type'       => 'service_account',
            'username'   => 'sa@serviceaccount.mixpanel.com',
            'password'   => 'sa-secret',
            'project_id' => '12345',
        },
        'data' => {
            'event' => 'Test Event',
            'properties' => {
                'Circumstances' => 'During a test',
                'distinct_id' => 'TEST ID',
                'mp_lib' => 'ruby',
                '$lib_version' => Mixpanel::VERSION,
                'token' => 'TEST TOKEN',
                'time' => @time_now.to_i * 1000
            }
        }
    }]])
  end

  it 'should send a well formed import/ message with project token credentials' do
    @events.import(
      { project_token: 'MY_PROJECT_TOKEN' },
      'TEST ID', 'Test Event', { 'Circumstances' => 'During a test' }
    )
    expect(@log).to eq([[:import, {
        'credentials' => {
            'type'  => 'project_token',
            'token' => 'MY_PROJECT_TOKEN',
        },
        'data' => {
            'event' => 'Test Event',
            'properties' => {
                'Circumstances' => 'During a test',
                'distinct_id' => 'TEST ID',
                'mp_lib' => 'ruby',
                '$lib_version' => Mixpanel::VERSION,
                'token' => 'TEST TOKEN',
                'time' => @time_now.to_i * 1000
            }
        }
    }]])
  end

  it 'should allow users to pass timestamp for import' do
    older_time = Time.parse('Jun 6 1971, 16:23:04')
    @events.import(
      { project_token: 'MY_PROJECT_TOKEN' },
      'TEST ID', 'Test Event',
      { 'Circumstances' => 'During a test', 'time' => older_time.to_i }
    )
    expect(@log).to eq([[:import, {
        'credentials' => {
            'type'  => 'project_token',
            'token' => 'MY_PROJECT_TOKEN',
        },
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
    }]])
  end

  it 'should accept string keys in credentials hash' do
    @events.import(
      { 'service_account_username' => 'sa@serviceaccount.mixpanel.com',
        'service_account_password' => 'sa-secret',
        'project_id'               => '12345' },
      'TEST ID', 'Test Event', { 'Circumstances' => 'During a test' }
    )
    expect(@log.first.first).to eq(:import)
    expect(@log.first.last.dig('credentials', 'type')).to eq('service_account')
  end

  it 'should raise ArgumentError with a clear message when credentials is a String' do
    expect {
      @events.import('OLD_API_KEY', 'TEST ID', 'Test Event')
    }.to raise_error(ArgumentError, /credentials must be a Hash.*got String/)
  end

  it 'should raise ArgumentError with a clear message when credentials is nil' do
    expect {
      @events.import(nil, 'TEST ID', 'Test Event')
    }.to raise_error(ArgumentError, /credentials must be a Hash.*got NilClass/)
  end

  it 'should raise ArgumentError when no recognised credential key is provided' do
    expect {
      @events.import({}, 'TEST ID', 'Test Event')
    }.to raise_error(ArgumentError, /credentials must include/)
  end

  it 'should raise ArgumentError when service account is missing password or project_id' do
    expect {
      @events.import({ service_account_username: 'u' }, 'TEST ID', 'Test Event')
    }.to raise_error(ArgumentError, /service account credentials missing required fields: service_account_password, project_id/)
  end

  it 'should raise ArgumentError when service account has blank project_id' do
    expect {
      @events.import({ service_account_username: 'u', service_account_password: 'p', project_id: '' }, 'TEST ID', 'Test Event')
    }.to raise_error(ArgumentError, /service account credentials missing required fields: project_id/)
  end

  it 'should raise ArgumentError when project_token is blank' do
    expect {
      @events.import({ project_token: '' }, 'TEST ID', 'Test Event')
    }.to raise_error(ArgumentError, /:project_token must not be blank/)
  end
end
