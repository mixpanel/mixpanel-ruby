require 'date'
require 'json'
require 'time'

require 'mixpanel-ruby/consumer'
require 'mixpanel-ruby/error'

module Mixpanel

  # Handles formatting Mixpanel profile updates and
  # sending them to the consumer. You will rarely need
  # to instantiate this class directly- to send
  # profile updates, use Mixpanel::Tracker#people
  #
  #     tracker = Mixpanel::Tracker.new(YOUR_MIXPANEL_TOKEN)
  #     tracker.people.set(...) # Or .append(..), or track_charge(...) etc.
  class People

    # You likely won't need to instantiate instances of Mixpanel::People
    # directly. The best way to get an instance of Mixpanel::People is
    #
    #     tracker = Mixpanel::Tracker.new(YOUR_MIXPANEL_TOKEN)
    #     tracker.people # An instance of Mixpanel::People
    #
    def initialize(token, error_handler=nil, &block)
      @token = token
      @error_handler = error_handler || ErrorHandler.new

      if block
        @sink = block
      else
        consumer = Consumer.new
        @sink = consumer.method(:send!)
      end
    end

    # Sets properties on a user record. Takes a Hash with string
    # keys, and values that are strings, numbers, booleans, or
    # DateTimes
    #
    #    tracker = Mixpanel::Tracker.new(YOUR_MIXPANEL_TOKEN)
    #    # Sets properties on profile with id "1234"
    #    tracker.people.set("1234", {
    #        'company' => 'Acme',
    #        'plan' => 'Premium',
    #        'Sign-Up Date' => DateTime.now
    #    });
    #
    # If you provide an ip argument, \Mixpanel will use that
    # ip address for geolocation (rather than the ip of your server)
    def set(distinct_id, properties, ip=nil, optional_params={})
      properties = fix_property_dates(properties)
      message = {
        '$distinct_id' => distinct_id,
        '$set' => properties,
      }.merge(optional_params)
      message['$ip'] = ip if ip

      update(message)
    end

    # set_once works just like #set, but will only change the
    # value of properties if they are not already present
    # in the profile. That means you can call set_once many times
    # without changing an original value.
    #
    #    tracker = Mixpanel::Tracker.new(YOUR_MIXPANEL_TOKEN)
    #    tracker.people.set_once("12345", {
    #        'First Login Date': DateTime.now
    #    });
    #
    def set_once(distinct_id, properties, ip=nil, optional_params={})
      properties = fix_property_dates(properties)
      message = {
        '$distinct_id' => distinct_id,
        '$set_once' => properties,
      }.merge(optional_params)
      message['$ip'] = ip if ip

      update(message)
    end

    # Changes the value of properties by a numeric amount.  Takes a
    # hash with string keys and numeric properties. \Mixpanel will add
    # the given amount to whatever value is currently assigned to the
    # property. If no property exists with a given name, the value
    # will be added to zero.
    #
    #    tracker = Mixpanel::Tracker.new(YOUR_MIXPANEL_TOKEN)
    #    tracker.people.increment("12345", {
    #        'Coins Spent' => 7,
    #        'Coins Earned' => -7, # Use a negative number to subtract
    #    });
    #
    def increment(distinct_id, properties, ip=nil, optional_params={})
      properties = fix_property_dates(properties)
      message = {
        '$distinct_id' => distinct_id,
        '$add' => properties,
      }.merge(optional_params)
      message['$ip'] = ip if ip

      update(message)
    end

    # Convenience method- increases the value of a numeric property
    # by one. Calling #plus_one(distinct_id, property_name) is the same as calling
    # #increment(distinct_id, {property_name => 1})
    #
    #    tracker = Mixpanel::Tracker.new(YOUR_MIXPANEL_TOKEN)
    #    tracker.people.plus_one("12345", "Albums Released")
    #
    def plus_one(distinct_id, property_name, ip=nil, optional_params={})
      increment(distinct_id, {property_name => 1}, ip, optional_params)
    end

    # Appends a values to the end of list-valued properties.
    # If the given properties don't exist, a new list-valued
    # property will be created.
    #
    #    tracker = Mixpanel::Tracker.new(YOUR_MIXPANEL_TOKEN)
    #    tracker.people.append("12345", {
    #        'Login Dates' => DateTime.now,
    #        'Alter Ego Names' => 'Ziggy Stardust'
    #    });
    #
    def append(distinct_id, properties, ip=nil, optional_params={})
      properties = fix_property_dates(properties)
      message = {
        '$distinct_id' => distinct_id,
        '$append' => properties,
      }.merge(optional_params)
      message['$ip'] = ip if ip

      update(message)
    end

    # Set union on list valued properties.
    # Associates a list containing all elements of a given list,
    # and all elements currently in a list associated with the given
    # property. After a union, every element in the list associated
    # with a property will be unique.
    #
    #    tracker = Mixpanel::Tracker.new(YOUR_MIXPANEL_TOKEN)
    #    tracker.people.union("12345", {
    #        'Levels Completed' => ['Suffragette City']
    #    });
    #
    def union(distinct_id, properties, ip=nil, optional_params={})
      properties = fix_property_dates(properties)
      message = {
        '$distinct_id' => distinct_id,
        '$union' => properties,
      }.merge(optional_params)
      message['$ip'] = ip if ip

      update(message)
    end

    # Removes properties and their values from a profile.
    #
    #    tracker = Mixpanel::Tracker.new(YOUR_MIXPANEL_TOKEN)
    #
    #    # removes a single property and its value from a profile
    #    tracker.people.unset("12345", "Overdue Since")
    #
    #    # removes multiple properties and their values from a profile
    #    tracker.people.unset("12345", ["Overdue Since", "Paid Date"])
    #
    def unset(distinct_id, properties, ip=nil, optional_params={})
      properties = [properties] unless properties.is_a?(Array)
      message = {
        '$distinct_id' => distinct_id,
        '$unset' => properties,
      }.merge(optional_params)
      message['$ip'] = ip if ip

      update(message)
    end

    # Records a payment to you to a profile. Charges recorded with
    # #track_charge will appear in the \Mixpanel revenue report.
    #
    #    tracker = Mixpanel::Tracker.new(YOUR_MIXPANEL_TOKEN)
    #
    #    # records a charge of $25.32 from user 12345
    #    tracker.people.track_charge("12345", 25.32)
    #
    #    # records a charge of $30.50 on the 2nd of January,
    #    mixpanel.people.track_charge("12345", 30.50, {
    #        '$time' => DateTime.parse("Jan 2 2013")
    #    })
    #
    def track_charge(distinct_id, amount, properties={}, ip=nil, optional_params={})
      properties = fix_property_dates(properties)
      charge_properties = properties.merge({'$amount' => amount})
      append(distinct_id, {'$transactions' => charge_properties}, ip, optional_params)
    end

    # Clear all charges from a \Mixpanel people profile
    def clear_charges(distinct_id, ip=nil, optional_params={})
      unset(distinct_id, '$transactions', ip, optional_params)
    end

    # Permanently delete a profile from \Mixpanel people analytics
    # To delete a user and ignore alias pass into optional params
    #   {"$ignore_alias"=>true}
    def delete_user(distinct_id, optional_params={})
      update({
        '$distinct_id' => distinct_id,
        '$delete' => '',
      }.merge(optional_params))
    end

    # Send a generic update to \Mixpanel people analytics.
    # Caller is responsible for formatting the update message, as
    # documented in the \Mixpanel HTTP specification, and passing
    # the message as a dict to #update. This
    # method might be useful if you want to use very new
    # or experimental features of people analytics from Ruby
    # The \Mixpanel HTTP tracking API is documented at
    # https://mixpanel.com/help/reference/http
    def update(message)
      data = {
        '$token' => @token,
        '$time' =>  ((Time.now.to_f) * 1000.0).to_i,
      }.merge(message)

      message = {'data' => data}

      ret = true
      begin
        @sink.call(:profile_update, message.to_json)
      rescue MixpanelError => e
        @error_handler.handle(e)
        ret = false
      end

      ret
    end

    private

    def fix_property_dates(properties)
      properties.inject({}) do |ret, (key, value)|
        value = value.respond_to?(:new_offset) ? value.new_offset('0') : value
        value = value.respond_to?(:utc) ? value.utc : value  # Handle ActiveSupport::TimeWithZone

        ret[key] = value.respond_to?(:strftime) ? value.strftime('%Y-%m-%dT%H:%M:%S') : value
        ret
      end
    end
  end
end
