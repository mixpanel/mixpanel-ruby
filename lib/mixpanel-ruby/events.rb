require 'mixpanel-ruby/consumer'
require 'time'

module Mixpanel

  # Handles formatting Mixpanel event tracking messages
  # and sending them to the consumer. Mixpanel::Tracker
  # is a subclass of this class, and the best way to
  # track events is to instantiate a Mixpanel::Tracker
  #
  #     tracker = Mixpanel::Tracker.new # Has all of the methods of Mixpanel::Event
  #     tracker.track(...)
  #
  class Events

    # You likely won't need to instantiate an instance of
    # Mixpanel::Events directly. The best way to get an instance
    # is to use Mixpanel::Tracker
    #
    #     # tracker has all of the methods of Mixpanel::Events
    #     tracker = Mixpanel::Tracker.new(...)
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

    # Notes that an event has occurred, along with a distinct_id
    # representing the source of that event (for example, a user id),
    # an event name describing the event and a set of properties
    # describing that event. Properties are provided as a Hash with
    # string keys and strings, numbers or booleans as values.
    #
    #     tracker = Mixpanel::Tracker.new
    #
    #     # Track that user "12345"'s credit card was declined
    #     tracker.track("12345", "Credit Card Declined")
    #
    #     # Properties describe the circumstances of the event,
    #     # or aspects of the source or user associated with the event
    #     tracker.track("12345", "Welcome Email Sent", {
    #         'Email Template' => 'Pretty Pink Welcome',
    #         'User Sign-up Cohort' => 'July 2013'
    #     })
    def track(distinct_id, event, properties={}, ip=nil)
      properties = {
          'distinct_id' => distinct_id,
          'token' => @token,
          'time' => Time.now.to_i,
          'mp_lib' => 'ruby',
          '$lib_version' => Mixpanel::VERSION
      }.merge(properties)
      if ip
        properties['ip'] = ip
      end

      data = {
        'event' => event,
        'properties' => properties
      }

      message = {
        'data' => data
      }

      @sink.call(:event, message.to_json)
    end

    # Imports an event that has occurred in the past, along with a distinct_id
    # representing the source of that event (for example, a user id),
    # an event name describing the event and a set of properties
    # describing that event. Properties are provided as a Hash with
    # string keys and strings, numbers or booleans as values.
    #
    #     tracker = Mixpanel::Tracker.new
    #
    #     # Track that user "12345"'s credit card was declined
    #     tracker.import("API_KEY", "12345", "Credit Card Declined")
    #
    #     # Properties describe the circumstances of the event,
    #     # or aspects of the source or user associated with the event
    #     tracker.import("API_KEY", "12345", "Welcome Email Sent", {
    #         'Email Template' => 'Pretty Pink Welcome',
    #         'User Sign-up Cohort' => 'July 2013'
    #     })
    def import(api_key, distinct_id, event, properties={}, ip=nil)
      properties = {
        'distinct_id' => distinct_id,
        'token' => @token,
        'time' => Time.now.to_i,
        'mp_lib' => 'ruby',
        '$lib_version' => Mixpanel::VERSION
      }.merge(properties)
      if ip
        properties['ip'] = ip
      end

      data = {
        'event' => event,
        'properties' => properties
      }

      message = {
        'data' => data,
        'api_key' => api_key
      }

      @sink.call(:import, message.to_json)
    end

    # Exports events from Mixpanel
    def export(secret_key, from_date = Time.now - 7*24*60*60, to_date = Time.now, events, bucket)
      message = {
        'api_key' => @token,
        'from_date' => from_date.strftime("%Y-%m-%d"),
        'to_date' => to_date.strftime("%Y-%m-%d"),
        'event' => events.to_json,
        'expire' => (Time.now + 10*60).to_i
      }

      message.merge(:bucket => bucket) if bucket

      args = message.keys.sort.map{ |key| "#{key}=#{message[key]}" }.join('')
      message = message.merge(:sig => Digest::MD5.hexdigest(args + secret_key))
      response_code, response_body = @sink.call(:export, message)

      if response_code == "200"
        return response_code, response_body.split("\n").map{ |row| JSON.parse(row)}
      end
      return response_code, response_body
    end
  end
end
