require 'spec_helper'
require 'mixpanel-ruby/people'

describe Mixpanel::People do
  before(:each) do
    @time_now = Time.parse('Jun 6 1972, 16:23:04')
    allow(Time).to receive(:now).and_return(@time_now)

    @log = []
    @people = Mixpanel::People.new('TEST TOKEN') do |type, message|
      @log << [type, JSON.load(message)]
    end
  end

  it 'should send a well formed engage/set message' do
    @people.set("TEST ID", {
        '$firstname' => 'David',
        '$lastname' => 'Bowie',
    })
    expect(@log).to eq([[:profile_update, 'data' => {
        '$token' => 'TEST TOKEN',
        '$distinct_id' => 'TEST ID',
        '$time' => @time_now.to_i * 1000,
        '$set' => {
            '$firstname' => 'David',
            '$lastname' => 'Bowie'
        }
    }]])
  end

  it 'should properly cast dates' do
    @people.set("TEST ID", {
        'created_at' => DateTime.new(2013, 1, 2, 3, 4, 5)
    })
    expect(@log).to eq([[:profile_update, 'data' => {
        '$token' => 'TEST TOKEN',
        '$distinct_id' => 'TEST ID',
        '$time' => @time_now.to_i * 1000,
        '$set' => {
            'created_at' => '2013-01-02T03:04:05'
        }
    }]])
  end

  it 'should convert offset datetimes to UTC' do
    @people.set("TEST ID", {
        'created_at' => DateTime.new(2013, 1, 1, 18, 4, 5, '-9')
    })
    expect(@log).to eq([[:profile_update, 'data' => {
        '$token' => 'TEST TOKEN',
        '$distinct_id' => 'TEST ID',
        '$time' => @time_now.to_i * 1000,
        '$set' => {
            'created_at' => '2013-01-02T03:04:05'
        }
    }]])
  end

  it 'should send a well formed engage/set_once message' do
    @people.set_once("TEST ID", {
        '$firstname' => 'David',
        '$lastname' => 'Bowie',
    })
    expect(@log).to eq([[:profile_update, 'data' => {
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
    @people.increment("TEST ID", {'Albums Released' => 10})
    expect(@log).to eq([[:profile_update, 'data' => {
        '$token' => 'TEST TOKEN',
        '$distinct_id' => 'TEST ID',
        '$time' => @time_now.to_i * 1000,
        '$add' => {
            'Albums Released' => 10
        }
    }]])
  end

  it 'should send an engage/add message with a value of 1' do
    @people.plus_one("TEST ID", 'Albums Released')
    expect(@log).to eq([[:profile_update, 'data' => {
        '$token' => 'TEST TOKEN',
        '$distinct_id' => 'TEST ID',
        '$time' => @time_now.to_i * 1000,
        '$add' => {
            'Albums Released' => 1
        }
    }]])
  end

  it 'should send a well formed engage/append message' do
    @people.append("TEST ID", {'Albums' => 'Diamond Dogs'})
    expect(@log).to eq([[:profile_update, 'data' => {
        '$token' => 'TEST TOKEN',
        '$distinct_id' => 'TEST ID',
        '$time' => @time_now.to_i * 1000,
        '$append' => {
            'Albums' => 'Diamond Dogs'
        }
    }]])
  end

  it 'should send a well formed engage/union message' do
    @people.union("TEST ID", {'Albums' => ['Diamond Dogs']})
    expect(@log).to eq([[:profile_update, 'data' => {
        '$token' => 'TEST TOKEN',
        '$distinct_id' => 'TEST ID',
        '$time' => @time_now.to_i * 1000,
        '$union' => {
            'Albums' => ['Diamond Dogs']
        }
    }]])
  end

  it 'should send a well formed unset message' do
    @people.unset('TEST ID', 'Albums')
    expect(@log).to eq([[:profile_update, 'data' => {
        '$token' => 'TEST TOKEN',
        '$distinct_id' => 'TEST ID',
        '$time' => @time_now.to_i * 1000,
        '$unset' => ['Albums']
    }]])
  end

  it 'should send a well formed unset message with multiple properties' do
    @people.unset('TEST ID', ['Albums', 'Vinyls'])
    expect(@log).to eq([[:profile_update, 'data' => {
        '$token' => 'TEST TOKEN',
        '$distinct_id' => 'TEST ID',
        '$time' => @time_now.to_i * 1000,
        '$unset' => ['Albums', 'Vinyls']
    }]])
  end

  it 'should send an engage/append with the right $transaction stuff' do
    @people.track_charge("TEST ID", 25.42, {
        '$time' => DateTime.new(1999,12,24,14, 02, 53),
        'SKU' => '1234567'
    })
    expect(@log).to eq([[:profile_update, 'data' => {
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
    expect(@log).to eq([[:profile_update, 'data' => {
        '$token' => 'TEST TOKEN',
        '$distinct_id' => 'TEST ID',
        '$time' => @time_now.to_i * 1000,
        '$unset' => ['$transactions']
    }]])
  end

  it 'should send a well formed engage/delete message' do
    @people.delete_user("TEST ID")
    expect(@log).to eq([[:profile_update, 'data' => {
        '$token' => 'TEST TOKEN',
        '$distinct_id' => 'TEST ID',
        '$time' => @time_now.to_i * 1000,
        '$delete' => ''
    }]])
  end

  it 'should send a well formed engage/delete message with blank optional_params' do
    @people.delete_user("TEST ID", {})
    expect(@log).to eq([[:profile_update, 'data' => {
        '$token' => 'TEST TOKEN',
        '$distinct_id' => 'TEST ID',
        '$time' => @time_now.to_i * 1000,
        '$delete' => ''
    }]])
  end

  it 'should send a well formed engage/delete message with ignore_alias true' do
    @people.delete_user("TEST ID", {"$ignore_alias"=>true})
    expect(@log).to eq([[:profile_update, 'data' => {
        '$token' => 'TEST TOKEN',
        '$distinct_id' => 'TEST ID',
        '$time' => @time_now.to_i * 1000,
        '$delete' => '',
        "$ignore_alias"=>true
    }]])
  end

  describe "batch operations" do

    it 'should send a well formed batch engage/set message' do
      @people.batch([{
          "TEST ID" => {
              '$set' => {
                  '$firstname' => 'David',
                  '$lastname' => 'Bowie',
              },
              '$unset' => ['Levels Completed']
          }
      }])
      expect(@log).to eq([
        [:profile_update, 'data' => [
          {
              '$token' => 'TEST TOKEN',
              '$time' => @time_now.to_i * 1000,
              '$distinct_id' => 'TEST ID',
              '$set' => {
                  '$firstname' => 'David',
                  '$lastname' => 'Bowie'
              }
          },
          {
              '$token' => 'TEST TOKEN',
              '$time' => @time_now.to_i * 1000,
              '$distinct_id' => 'TEST ID',
              '$unset' => ['Levels Completed']
          },
        ]
      ]])
    end

    it 'should send batch engage/ message in batches of 50' do
      profile_updates = 75.times.map do |i|
        { "TEST ID" => { '$set' => { "prop_#{i}" => 'David' } } }
      end

      batches = 75.times.map do |i|
        {
            '$token' => 'TEST TOKEN',
            '$distinct_id' => 'TEST ID',
            '$time' => @time_now.to_i * 1000,
            '$set' => { "prop_#{i}" => 'David' }
        }
      end

      @people.batch(profile_updates)
      expect(@log).to eq([
        [:profile_update, 'data' => batches[0, 50]],
        [:profile_update, 'data' => batches[50, 25]]
      ])
    end

    it 'should reject invalid operations' do
      @people.batch([{
          'TEST ID' => {
              '$set' => {
                  '$firstname' => 'David',
                  '$lastname' => 'Bowie',
              },
              '$foo' => {
                  '$bar' => 'baz',
              }
          }
      }])
      expect(@log).to eq([[:profile_update, 'data' => [{
          '$token' => 'TEST TOKEN',
          '$distinct_id' => 'TEST ID',
          '$time' => @time_now.to_i * 1000,
          '$set' => {
              '$firstname' => 'David',
              '$lastname' => 'Bowie'
          }
      }]]])
    end
  end

end
