require 'spec_helper'
require 'date'
require 'json'
require 'mixpanel-ruby/people.rb'

describe Mixpanel::People do
  before(:each) do
    @time_now = Time.parse('Jun 6 1972, 16:23:04')
    Time.stub!(:now).and_return(@time_now)

    @log = []
    @people = Mixpanel::People.new('TEST TOKEN') do |type, message|
      @log << [ type, JSON.load(message['data']) ]
    end
  end

  it 'should send a well formed engage/set message' do
    @people.set("TEST ID", {
        '$firstname' => 'David',
        '$lastname' => 'Bowie',
    })
    @log.should eq([[ :profile_update, {
        '$token' => 'TEST TOKEN',
        '$distinct_id' => 'TEST ID',
        '$time' => @time_now.to_i * 1000,
        '$set' => {
            '$firstname' => 'David',
            '$lastname' => 'Bowie'
        }
    }]])
  end

  it 'should send a well formed engage/set_once message' do
    @people.set_once("TEST ID", {
        '$firstname' => 'David',
        '$lastname' => 'Bowie',
    })
    @log.should eq([[ :profile_update, {
        '$token' => 'TEST TOKEN',
        '$distinct_id' => 'TEST ID',
        '$time' => @time_now.to_i * 1000,
        '$set_once' => {
            '$firstname' => 'David',
            '$lastname' => 'Bowie'
        }
    }]])
  end

  it 'should send a well formed engage/add message' do
    @people.increment("TEST ID", { 'Albums Released' => 10 })
    @log.should eq([[ :profile_update, {
        '$token' => 'TEST TOKEN',
        '$distinct_id' => 'TEST ID',
        '$time' => @time_now.to_i * 1000,
        '$add' => {
            'Albums Released' => 10
        }
    }]])
  end

  it 'should send a well formed engage/append message' do
    @people.append("TEST ID", { 'Albums' => 'Diamond Dogs' })
    @log.should eq([[ :profile_update, {
        '$token' => 'TEST TOKEN',
        '$distinct_id' => 'TEST ID',
        '$time' => @time_now.to_i * 1000,
        '$append' => {
            'Albums' => 'Diamond Dogs'
        }
    }]])
  end

  it 'should send a well formed engage/union message' do
    @people.union("TEST ID", { 'Albums' => 'Diamond Dogs' })
    @log.should eq([[ :profile_update, {
        '$token' => 'TEST TOKEN',
        '$distinct_id' => 'TEST ID',
        '$time' => @time_now.to_i * 1000,
        '$union' => {
            'Albums' => 'Diamond Dogs'
        }
    }]])
  end

  it 'should send a well formed unset message' do
    @people.unset('TEST ID', 'Albums')
    @log.should eq([[ :profile_update, {
        '$token' => 'TEST TOKEN',
        '$distinct_id' => 'TEST ID',
        '$time' => @time_now.to_i * 1000,
        '$unset' => [ 'Albums' ]
    }]])
  end

  it 'should send an engage/append with the right $transaction stuff' do
    @people.track_charge("TEST ID", 25.42, {
        '$time' => DateTime.new(1999,12,24,14, 02, 53),
        'SKU' => '1234567'
    })
    @log.should eq([[ :profile_update, {
        '$token' => 'TEST TOKEN',
        '$distinct_id' => 'TEST ID',
        '$time' => @time_now.to_i * 1000,
        '$append' => {
            '$transactions' => {
                '$time' => '1999-12-24T14:02:53',
                'SKU' => '1234567',
                '$amount' => 25.42
            }
        }
    }]])
  end

  it 'should send a well formed engage/unset message for $transaction' do
    @people.clear_charges("TEST ID")
    @log.should eq([[ :profile_update, {
        '$token' => 'TEST TOKEN',
        '$distinct_id' => 'TEST ID',
        '$time' => @time_now.to_i * 1000,
        '$unset' => [ '$transactions' ]
    }]])
  end

  it 'should send a well formed engage/delete message' do
    @people.delete_user("TEST ID")
    @log.should eq([[ :profile_update, {
        '$token' => 'TEST TOKEN',
        '$distinct_id' => 'TEST ID',
        '$time' => @time_now.to_i * 1000,
        '$delete' => ''
    }]])
  end
end
