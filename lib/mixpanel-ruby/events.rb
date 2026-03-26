require 'time'

require 'mixpanel-ruby/consumer'
require 'mixpanel-ruby/error'

module Mixpanel

  # Handles formatting Mixpanel event tracking messages
  # and sending them to the consumer. Mixpanel::Tracker
  # is a subclass of this class, and the best way to
  # track events is to instantiate a Mixpanel::Tracker
  #
  #     tracker = Mixpanel::Tracker.new(YOUR_MIXPANEL_TOKEN) # Has all of the methods of Mixpanel::Event
  #     tracker.track(...)
  #
  class Events

    # You likely won't need to instantiate an instance of
    # Mixpanel::Events directly. The best way to get an instance
    # is to use Mixpanel::Tracker
    #
    #     # tracker has all of the methods of Mixpanel::Events
    #     tracker = Mixpanel::Tracker.new(YOUR_MIXPANEL_TOKEN)
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

    # Notes that an event has occurred, along with a distinct_id
    # representing the source of that event (for example, a user id),
    # an event name describing the event and a set of properties
    # describing that event. Properties are provided as a Hash with
    # string keys and strings, numbers or booleans as values.
    #
    #     tracker = Mixpanel::Tracker.new(YOUR_MIXPANEL_TOKEN)
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
        'time' => (Time.now.to_f * 1000).to_i,
        'mp_lib' => 'ruby',
        '$lib_version' => Mixpanel::VERSION,
      }.merge(properties)
      properties['ip'] = ip if ip

      data = {
        'event' => event,
        'properties' => properties,
      }

      message = {'data' => data}

      ret = true
      begin
        @sink.call(:event, message.to_json)
      rescue MixpanelError => e
        @error_handler.handle(e)
        ret = false
      end

      ret
    end

    # Imports an event that has occurred in the past, along with a distinct_id
    # representing the source of that event (for example, a user id),
    # an event name describing the event and a set of properties
    # describing that event. Properties are provided as a Hash with
    # string keys and strings, numbers or booleans as values.  By default,
    # we pass the time of the method call as the time the event occured, if you
    # wish to override this pass a timestamp in the properties hash.
    #
    # The credentials argument must be a Hash specifying one of two
    # authentication methods:
    #
    # Service account (recommended):
    #
    #     tracker.import(
    #       { service_account_username: 'sa@serviceaccount.mixpanel.com',
    #         service_account_password: 'sa-secret',
    #         project_id: '12345' },
    #       "12345", "Credit Card Declined", { 'time' => 1310111365 }
    #     )
    #
    # Project token (token sent as Basic Auth username, empty password):
    #
    #     tracker.import(
    #       { project_token: YOUR_MIXPANEL_TOKEN },
    #       "12345", "Credit Card Declined", { 'time' => 1310111365 }
    #     )
    def import(credentials, distinct_id, event, properties={}, ip=nil)
      credentials_data = if credentials[:service_account_username]
        {
          'type'       => 'service_account',
          'username'   => credentials[:service_account_username],
          'password'   => credentials[:service_account_password],
          'project_id' => credentials[:project_id].to_s,
        }
      elsif credentials[:project_token]
        {
          'type'  => 'project_token',
          'token' => credentials[:project_token],
        }
      else
        raise ArgumentError, "credentials must include :service_account_username/:service_account_password/:project_id or :project_token"
      end

      properties = {
        'distinct_id' => distinct_id,
        'token' => @token,
        'time' => (Time.now.to_f * 1000).to_i,
        'mp_lib' => 'ruby',
        '$lib_version' => Mixpanel::VERSION,
      }.merge(properties)
      properties['ip'] = ip if ip

      data = {
        'event' => event,
        'properties' => properties,
      }

      message = {
        'data'        => data,
        'credentials' => credentials_data,
      }

      ret = true
      begin
        @sink.call(:import, message.to_json)
      rescue MixpanelError => e
        @error_handler.handle(e)
        ret = false
      end

      ret
    end
  end
end
