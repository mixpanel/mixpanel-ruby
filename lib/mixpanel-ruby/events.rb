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
    def initialize(token, error_handler=nil, credentials: nil, &block)
      @token = token
      @error_handler = error_handler || ErrorHandler.new
      @credentials = credentials

      if block && credentials
        warn '[WARNING] credentials passed to Events/Tracker are ignored when a custom sink block is provided. Pass credentials to your consumer directly.'
      end

      if block
        @sink = block
      else
        consumer = Consumer.new(credentials: credentials)
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
    #     # Recommended: Use import_events() instead
    #     credentials = Mixpanel::ServiceAccountCredentials.new(username, secret, project_id)
    #     tracker = Mixpanel::Tracker.new(YOUR_MIXPANEL_TOKEN, credentials: credentials)
    #     tracker.import_events("12345", "Welcome Email Sent", {
    #         'Email Template' => 'Pretty Pink Welcome',
    #         'User Sign-up Cohort' => 'July 2013',
    #         'time' => 1369353600,
    #     })
    #
    #     # Legacy: Pass API key as first parameter (deprecated)
    #     tracker.import("API_KEY", "12345", "Credit Card Declined")
    #
    def import(api_key, distinct_id, event, properties={}, ip=nil)
      # Warn about deprecated API key usage
      if api_key && !api_key.to_s.empty?
        warn '[DEPRECATION] Passing api_key to import() is deprecated. Use ServiceAccountCredentials in the constructor instead. See https://docs.mixpanel.com/docs/tracking-methods/sdks/ruby#service-account-authentication'
      end

      # Warn when using import(nil, ...) - recommend import_events instead
      if api_key.nil? && @credentials
        warn '[DEPRECATION] Using import(nil, ...) is deprecated. Use import_events(...) instead for cleaner API.'
      end

      # Delegate to internal implementation
      import_internal(api_key, distinct_id, event, properties, ip)
    end

    # Import an event using service account credentials from the constructor.
    # This is the recommended method for importing historical events with service accounts.
    #
    # Credentials must be provided in the Tracker/Events constructor. This method is cleaner
    # than import() as it doesn't require passing nil as the first parameter.
    #
    #     credentials = Mixpanel::ServiceAccountCredentials.new(username, secret, project_id)
    #     tracker = Mixpanel::Tracker.new(YOUR_MIXPANEL_TOKEN, credentials: credentials)
    #
    #     tracker.import_events('user123', 'Past Event', {
    #         'time' => 1369353600,
    #         'Source' => 'Import'
    #     })
    #
    def import_events(distinct_id, event, properties={}, ip=nil)
      unless @credentials
        raise ArgumentError, 'import_events requires credentials in constructor. Use: Tracker.new(token, credentials: credentials)'
      end

      # Delegate to internal implementation with nil api_key (uses constructor credentials)
      import_internal(nil, distinct_id, event, properties, ip)
    end

    private

    # Internal implementation for importing events.
    # Called by both import() and import_events().
    def import_internal(api_key, distinct_id, event, properties, ip)
      # Validate that at least one authentication method is provided
      if api_key.nil? && @credentials.nil?
        raise ArgumentError, 'import requires authentication: provide either api_key parameter or credentials in constructor'
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
        'data' => data,
      }

      # Only include api_key in message if provided (legacy auth)
      # When using service account credentials (recommended), pass nil for api_key
      # and the Consumer will use credentials from its instance variable
      if api_key
        message['api_key'] = api_key
      end

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
