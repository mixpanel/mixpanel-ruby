require 'date'
require 'json'
require 'time'

require 'mixpanel-ruby/consumer'
require 'mixpanel-ruby/error'

module Mixpanel

  # Handles formatting Mixpanel group updates and
  # sending them to the consumer. You will rarely need
  # to instantiate this class directly- to send
  # group updates, use Mixpanel::Tracker#groups
  #
  #     tracker = Mixpanel::Tracker.new(YOUR_MIXPANEL_TOKEN)
  #     tracker.groups.set(...) or .set_once(..), or .delete(...) etc.
  class Groups

    # You likely won't need to instantiate instances of Mixpanel::Groups
    # directly. The best way to get an instance of Mixpanel::Groups is
    #
    #     tracker = Mixpanel::Tracker.new(YOUR_MIXPANEL_TOKEN)
    #     tracker.groups # An instance of Mixpanel::Groups
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

    # Sets properties on a group record. Takes a Hash with string
    # keys, and values that are strings, numbers, booleans, or
    # DateTimes
    #
    #    tracker = Mixpanel::Tracker.new(YOUR_MIXPANEL_TOKEN)
    #    # Sets properties on group with id "1234"
    #    tracker.groups.set("GROUP KEY", "1234", {
    #        'company' => 'Acme',
    #        'plan' => 'Premium',
    #        'Sign-Up Date' => DateTime.now
    #    });
    #
    # If you provide an ip argument, \Mixpanel will use that
    # ip address for geolocation (rather than the ip of your server)
    def set(group_key, group_id, properties, ip=nil, optional_params={})
      properties = fix_property_dates(properties)
      message = {
        '$group_key' => group_key,
        '$group_id' => group_id,
        '$set' => properties,
      }.merge(optional_params)
      message['$ip'] = ip if ip

      update(message)
    end

    # set_once works just like #set, but will only change the
    # value of properties if they are not already present
    # in the group. That means you can call set_once many times
    # without changing an original value.
    #
    #    tracker = Mixpanel::Tracker.new(YOUR_MIXPANEL_TOKEN)
    #    tracker.groups.set_once("GROUP KEY", "1234", {
    #        'First Login Date': DateTime.now
    #    });
    #
    def set_once(group_key, group_id, properties, ip=nil, optional_params={})
      properties = fix_property_dates(properties)
      message = {
        '$group_key' => group_key,
        '$group_id' => group_id,
        '$set_once' => properties,
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
    #    tracker.groups.union("GROUP KEY", "1234", {
    #        'Levels Completed' => ['Suffragette City']
    #    });
    #
    def union(group_key, group_id, properties, ip=nil, optional_params={})
      properties = fix_property_dates(properties)
      message = {
        '$group_key' => group_key,
        '$group_id' => group_id,
        '$union' => properties,
      }.merge(optional_params)
      message['$ip'] = ip if ip

      update(message)
    end

    # Removes properties and their values from a group.
    #
    #    tracker = Mixpanel::Tracker.new(YOUR_MIXPANEL_TOKEN)
    #
    #    # removes a single property and its value from a group
    #    tracker.groups.unset("GROUP KEY", "1234", "Overdue Since")
    #
    #    # removes multiple properties and their values from a group
    #    tracker.groups.unset("GROUP KEY",
    #                         "1234",
    #                         ["Overdue Since", "Paid Date"])
    #
    def unset(group_key, group_id, properties, ip=nil, optional_params={})
      properties = [properties] unless properties.is_a?(Array)
      message = {
        '$group_key' => group_key,
        '$group_id' => group_id,
        '$unset' => properties,
      }.merge(optional_params)
      message['$ip'] = ip if ip

      update(message)
    end

    # Permanently delete a group from \Mixpanel groups analytics
    def delete_group(group_key, group_id, optional_params={})
      update({
        '$group_key' => group_key,
        '$group_id' => group_id,
        '$delete' => '',
      }.merge(optional_params))
    end

    # Send a generic update to \Mixpanel groups analytics.
    # Caller is responsible for formatting the update message, as
    # documented in the \Mixpanel HTTP specification, and passing
    # the message as a dict to #update. This
    # method might be useful if you want to use very new
    # or experimental features of groups analytics from Ruby
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
        @sink.call(:group_update, message.to_json)
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
