require 'mixpanel-ruby/consumer'
require 'json'
require 'date'
require 'time'

module Mixpanel

  # Handles formatting Mixpanel profile updates and
  # sending them to the consumer. You will rarely need
  # to instantiate this class directly- to send
  # profile updates, use Mixpanel::Tracker#people
  #
  #     tracker = Mixpanel::Tracker.new
  #     tracker.people.set(...) # Or .append(..), or track_charge(...) etc.
  class People

    # You likely won't need to instantiate instances of Mixpanel::People
    # directly. The best way to get an instance of Mixpanel::People is
    #
    #     tracker = Mixpanel::Tracker.new(...)
    #     tracker.people # An instance of Mixpanel::People
    #
    def initialize(token, &block)
      @token = token
      if block
        @sink = block
      else
        consumer = Consumer.new
        @sink = consumer.method(:send)
      end
    end

    # Sets properties on a user record. Takes a Hash with string
    # keys, and values that are strings, numbers, booleans, or
    # DateTimes
    #
    #    tracker = Mixpanel::Tracker.new
    #    # Sets properties on profile with id "1234"
    #    tracker.people.set("1234", {
    #        'company' => 'Acme',
    #        'plan' => 'Premium',
    #        'Sign-Up Date' => DateTime.now
    #    });
    #
    # If you provide an ip argument, Mixpanel will use that
    # ip address for geolocation (rather than the ip of your server)
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

    # set_once works just like #set, but will only change the
    # value of properties if they are not already present
    # in the profile. That means you can call set_once many times
    # without changing an original value.
    #
    #    tracker = Mixpanel::Tracker.new
    #    tracker.people.set("12345", {
    #        'First Login Date': DateTime.now
    #    });
    #
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

    # Changes the value of properties by a numeric amount.  Takes a
    # hash with string keys and numeric properties.  Mixpanel will add
    # the given amount to whatever value is currently assigned to the
    # property. If no property exists with a given name, the value
    # will be added to zero.
    #
    #    tracker = Mixpanel::Tracker.new
    #    tracker.people.set("12345", {
    #        'Coins Spent' => 7,
    #        'Coins Earned' => -7, # Use a negative number to subtract
    #    });
    #
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

    # Appends a values to the end of list-valued properties.
    # If the given properties don't exist, a new list-valued
    # property will be created.
    #
    #    tracker = Mixpanel::Tracker.new
    #    tracker.people.append("12345", {
    #        'Login Dates' => DateTime.now,
    #        'Alter Ego Names' => 'Ziggy Stardust'
    #    });
    #
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

    # Appends a value to the end of list-valued properties,
    # only if the given value is not already present in the list.
    #
    #    tracker = Mixpanel::Tracker.new
    #    tracker.people.union("12345", {
    #        'Levels Completed' => 'Suffragette City'
    #    });
    #
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

    # Removes a property and it's value from a profile.
    #
    #    tracker = Mixpanel::Tracker.new
    #    tracker.people.unset("12345", "Overdue Since")
    #
    def unset(distinct_id, property)
      update({
          '$distinct_id' => distinct_id,
          '$unset' => [ property ]
      })
    end

    # Records a payment to you to a profile. Charges recorded with
    # #track_charge will appear in the Mixpanel revenue report.
    #
    #    tracker = Mixpanel::Tracker.new
    #
    #    # records a charge of $25.32 from user 12345
    #    tracker.people.track_charge("12345", 25.32)
    #
    #    # records a charge of $30.50 on the 2nd of January,
    #    mixpanel.people.track_charge("12345", 30.50, {
    #        '$time' => DateTime.parse("Jan 2 2013")
    #    })
    #
    def track_charge(distinct_id, amount, properties, ip=nil)
      properties = fix_property_dates(properties)
      charge_properties = properties.merge({ '$amount' => amount })
      append(distinct_id, { '$transactions' => charge_properties }, ip)
    end

    # Clear all charges from a Mixpanel people profile
    def clear_charges(distinct_id)
      unset(distinct_id, '$transactions')
    end

    # Permanently delete a profile from Mixpanel people analytics
    def delete_user(distinct_id)
      update({
          '$distinct_id' => distinct_id,
          '$delete' => ''
      })
    end

    # Send a generic update to Mixpanel people analytics.
    # Caller is responsible for formatting the update, as
    # documented in the Mixpanel HTTP specification. This
    # method might be useful if you want to use very new
    # or experimental features of people analytics from Ruby
    # The Mixpanel HTTP tracking API is documented at
    # http://joe.dev.mixpanel.org/help/reference/http
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
  end
end
