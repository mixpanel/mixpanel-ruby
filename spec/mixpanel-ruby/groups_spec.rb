require 'spec_helper'
require 'active_support/time'

require 'mixpanel-ruby/groups'

describe Mixpanel::Groups do
  before(:each) do
    @time_now = Time.parse('Jun 6 1972, 16:23:04')
    allow(Time).to receive(:now).and_return(@time_now)

    @log = []
    @groups = Mixpanel::Groups.new('TEST TOKEN') do |type, message|
      @log << [type, JSON.load(message)]
    end
  end

  it 'should send a well formed groups/set message' do
    @groups.set("TEST GROUP KEY", "TEST GROUP ID", {
        '$groupname' => 'Mixpanel',
        '$grouprevenue' => 200
    })
    expect(@log).to eq([[:group_update, 'data' => {
        '$token' => 'TEST TOKEN',
        '$group_key' => 'TEST GROUP KEY',
        '$group_id' => 'TEST GROUP ID',
        '$time' => @time_now.to_i * 1000,
        '$set' => {
            '$groupname' => 'Mixpanel',
            '$grouprevenue' => 200
        }
    }]])
  end

  it 'should properly cast dates' do
    @groups.set("TEST GROUP KEY", "TEST GROUP ID", {
        'created_at' => DateTime.new(2013, 1, 2, 3, 4, 5)
    })
    expect(@log).to eq([[:group_update, 'data' => {
        '$token' => 'TEST TOKEN',
        '$group_key' => 'TEST GROUP KEY',
        '$group_id' => 'TEST GROUP ID',
        '$time' => @time_now.to_i * 1000,
        '$set' => {
            'created_at' => '2013-01-02T03:04:05'
        }
    }]])
  end

  it 'should convert offset datetimes to UTC' do
    @groups.set("TEST GROUP KEY", "TEST GROUP ID", {
        'created_at' => DateTime.new(2013, 1, 1, 18, 4, 5, '-8')
    })
    expect(@log).to eq([[:group_update, 'data' => {
        '$token' => 'TEST TOKEN',
        '$group_key' => 'TEST GROUP KEY',
        '$group_id' => 'TEST GROUP ID',
        '$time' => @time_now.to_i * 1000,
        '$set' => {
            'created_at' => '2013-01-02T02:04:05'
        }
    }]])
  end

  it 'should convert offset ActiveSupport::TimeWithZone objects to UTC' do
    Time.zone = 'Pacific Time (US & Canada)'
    @groups.set("TEST GROUP KEY", "TEST GROUP ID", {
        'created_at' => Time.zone.local(2013, 1, 1, 18, 4, 5)
    })
    expect(@log).to eq([[:group_update, 'data' => {
        '$token' => 'TEST TOKEN',
        '$group_key' => 'TEST GROUP KEY',
        '$group_id' => 'TEST GROUP ID',
        '$time' => @time_now.to_i * 1000,
        '$set' => {
            'created_at' => '2013-01-02T02:04:05'
        }
    }]])
  end

  it 'should send a well formed groups/set_once message' do
    @groups.set_once("TEST GROUP KEY", "TEST GROUP ID", {
        '$groupname' => 'Mixpanel',
        '$grouprevenue' => 200
    })
    expect(@log).to eq([[:group_update, 'data' => {
        '$token' => 'TEST TOKEN',
        '$group_key' => 'TEST GROUP KEY',
        '$group_id' => 'TEST GROUP ID',
        '$time' => @time_now.to_i * 1000,
        '$set_once' => {
            '$groupname' => 'Mixpanel',
            '$grouprevenue' => 200
        }
    }]])
  end

  it 'should send a well formed groups/remove message' do
    @groups.remove("TEST GROUP KEY", "TEST GROUP ID", {
        'Albums' => 'Diamond Dogs'
    })
    expect(@log).to eq([[:group_update, 'data' => {
        '$token' => 'TEST TOKEN',
        '$group_key' => 'TEST GROUP KEY',
        '$group_id' => 'TEST GROUP ID',
        '$time' => @time_now.to_i * 1000,
        '$remove' => {
            'Albums' => 'Diamond Dogs'
        }
    }]])
  end

  it 'should send a well formed groups/union message' do
    @groups.union("TEST GROUP KEY", "TEST GROUP ID", {
      'Albums' => ['Diamond Dogs']
    })
    expect(@log).to eq([[:group_update, 'data' => {
        '$token' => 'TEST TOKEN',
        '$group_key' => 'TEST GROUP KEY',
        '$group_id' => 'TEST GROUP ID',
        '$time' => @time_now.to_i * 1000,
        '$union' => {
            'Albums' => ['Diamond Dogs']
        }
    }]])
  end

  it 'should send a well formed unset message' do
    @groups.unset("TEST GROUP KEY", "TEST GROUP ID", 'Albums')
    expect(@log).to eq([[:group_update, 'data' => {
        '$token' => 'TEST TOKEN',
        '$group_key' => 'TEST GROUP KEY',
        '$group_id' => 'TEST GROUP ID',
        '$time' => @time_now.to_i * 1000,
        '$unset' => ['Albums']
    }]])
  end

  it 'should send a well formed unset message with multiple properties' do
    @groups.unset("TEST GROUP KEY", "TEST GROUP ID", ['Albums', 'Vinyls'])
    expect(@log).to eq([[:group_update, 'data' => {
        '$token' => 'TEST TOKEN',
        '$group_key' => 'TEST GROUP KEY',
        '$group_id' => 'TEST GROUP ID',
        '$time' => @time_now.to_i * 1000,
        '$unset' => ['Albums', 'Vinyls']
    }]])
  end

  it 'should send a well formed groups/delete message' do
    @groups.delete_group("TEST GROUP KEY", "TEST GROUP ID")
    expect(@log).to eq([[:group_update, 'data' => {
        '$token' => 'TEST TOKEN',
        '$group_key' => 'TEST GROUP KEY',
        '$group_id' => 'TEST GROUP ID',
        '$time' => @time_now.to_i * 1000,
        '$delete' => ''
    }]])
  end
end
