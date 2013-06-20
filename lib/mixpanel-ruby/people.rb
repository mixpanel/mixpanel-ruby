require 'mixpanel-ruby/consumer'
require 'json'
require 'date'
require 'time'

module Mixpanel
  class PeopleDate
    def initialize(date)
      @date = date
    end

    def to_json(*a)
      @date.strftime('%Y-%m-%dT%H:%M:%S').to_json(*a)
    end

    def self.asPeopleDate(thing)
      if thing.is_a?(Date)
        PeopleDate.new(thing)
      else
        thing
      end
    end
  end

  class People
    def initialize(token, consumer=nil, &block)
      @token = token
      if block
        @sink = block
      elsif consumer
        @sink = consumer.method(:send)
      else
        consumer = Consumer.new
        @sink = consumer.method(:send)
      end
    end

    def set(distinct_id, properties, ip=nil)
      properties = fix_property_dates(properties)
      message = {
          '$distinct_id' => distinct_id,
          '$set' => properties,
      }

      if ip
        message['$ip'] = ip
      end

      update(message)
    end

    def set_once(distinct_id, properties, ip=nil)
      properties = fix_property_dates(properties)
      message = {
          '$distinct_id' => distinct_id,
          '$set_once' => properties,
      }

      if ip
        message['$ip'] = ip
      end

      update(message)
    end

    def increment(distinct_id, properties, ip=nil)
      properties = fix_property_dates(properties)
      message = {
          '$distinct_id' => distinct_id,
          '$add' => properties,
      }

      if ip
        message['$ip'] = ip
      end

      update(message)
    end

    def append(distinct_id, properties, ip=nil)
      properties = fix_property_dates(properties)
      message = {
          '$distinct_id' => distinct_id,
          '$append' => properties,
      }

      if ip
        message['$ip'] = ip
      end

      update(message)
    end

    def union(distinct_id, properties, ip=nil)
      properties = fix_property_dates(properties)
      message = {
          '$distinct_id' => distinct_id,
          '$union' => properties,
      }

      if ip
        message['$ip'] = ip
      end

      update(message)
    end

    def unset(distinct_id, property)
      update({
          '$distinct_id' => distinct_id,
          '$unset' => [ property ]
      })
    end

    def track_charge(distinct_id, amount, properties, ip=nil)
      properties = fix_property_dates(properties)
      charge_properties = properties.merge({ '$amount' => amount })
      append(distinct_id, { '$transactions' => charge_properties }, ip)
    end

    def clear_charges(distinct_id)
      unset(distinct_id, '$transactions')
    end

    def delete_user(distinct_id)
      update({
          '$distinct_id' => distinct_id,
          '$delete' => ''
      })
    end

    def update(message)
      message = {
          '$token' => @token,
          '$time' =>  ((Time.now.to_f) * 1000.0).to_i
      }.merge(message)
      @sink.call(:profile_update, message.to_json)
    end

    private

    def fix_property_dates(h)
      h.inject({}) do |ret,(k,v)|
        ret[k] = PeopleDate.asPeopleDate(v)
        ret
      end
    end
  end
end
