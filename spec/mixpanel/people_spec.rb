require 'spec_helper'
require 'date'
require 'mixpanel/people.rb'

describe MixpanelPeople do
  before(:each) do
    @log = LogConsumer.new
    @people = MixpanelPeople.new('TEST TOKEN', { :consumer => @log })
  end

  it 'should send a well formed engage/set message' do
    @people.set("TEST ID", {
        '$firstname' => 'David',
        '$lastname' => 'Bowie',
    })
    @log.messages.should eq([{
        '$token' => 'TEST TOKEN',
        '$distinct_id' => 'TEST ID',
        '$set' => {
            '$firstname' => 'David',
            '$lastname' => 'Bowie'
        }
    }])
  end

  it 'should send a well formed engage/set_once message' do
    @people.set_once("TEST ID", {
        '$firstname' => 'David',
        '$lastname' => 'Bowie',
    })
    @log.messages.should eq([{
        '$token' => 'TEST TOKEN',
        '$distinct_id' => 'TEST ID',
        '$set_once' => {
            '$firstname' => 'David',
            '$lastname' => 'Bowie'
        }
    }])
  end

  it 'should send a well formed engage/add message' do
    @people.increment("TEST ID", { 'Albums Released' => 10 })
    @log.messages.should eq([{
        '$token' => 'TEST TOKEN',
        '$distinct_id' => 'TEST ID',
        '$add' => {
            'Albums Released' => 10
        }
    }])
  end

  it 'should send a well formed engage/append message' do
    @people.append("TEST ID", { 'Albums' => 'Diamond Dogs' })
    @log.messages.should eq([{
        '$token' => 'TEST TOKEN',
        '$distinct_id' => 'TEST ID',
        '$append' => {
            'Albums' => 'Diamond Dogs'
        }
    }])
  end

  it 'should send a well formed engage/union message' do
    @people.union("TEST ID", { 'Albums' => 'Diamond Dogs' })
    @log.messages.should eq([{
        '$token' => 'TEST TOKEN',
        '$distinct_id' => 'TEST ID',
        '$union' => {
            'Albums' => 'Diamond Dogs'
        }
    }])
  end

  it 'should send an engage/append with the right $transaction stuff' do
    @people.track_charge("TEST ID", 25.42, {
        '$time' => DateTime.new(1999,12,24,14, 02, 53),
        'SKU' => '1234567'
    })
    @log.messages.should eq([{
        '$token' => 'TEST TOKEN',
        '$distinct_id' => 'TEST ID',
        '$append' => {
            '$transactions' => {
                '$time' => '1999-12-24T14:02:53',
                'SKU' => '1234567',
                '$amount' => 25.42
            }
        }
    }])
  end

  it 'should send a well formed engage/unset message for $transaction' do
    @people.clear_charges("TEST ID")
    @log.messages.should eq([{
        '$token' => 'TEST TOKEN',
        '$distinct_id' => 'TEST ID',
        '$unset' => [ '$transactions' ]
    }])
  end

  it 'should send a well formed engage/delete message' do
    @people.delete_user("TEST ID")
    @log.messages.should eq([{
        '$token' => 'TEST TOKEN',
        '$distinct_id' => 'TEST ID',
        '$delete' => ''
    }])
  end
end
