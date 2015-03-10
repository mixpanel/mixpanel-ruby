require 'mixpanel-ruby/events.rb'
require 'mixpanel-ruby/people.rb'

module Mixpanel
  # Use Mixpanel::Tracker to track events and profile updates in your application.
  # To track an event, call
  #
  #     tracker = Mixpanel::Tracker.new(YOUR_MIXPANEL_TOKEN)
  #     Mixpanel::Tracker.track(a_distinct_id, an_event_name, {properties})
  #
  # To send people updates, call
  #
  #     tracker = Mixpanel::Tracker.new(YOUR_MIXPANEL_TOKEN)
  #     tracker.people.set(a_distinct_id, {properties})
  #
  # You can find your project token in the settings dialog for your
  # project, inside of the Mixpanel web application.
  #
  # Mixpanel::Tracker is a subclass of Mixpanel::Events, and exposes
  # an instance of Mixpanel::People as Tracker#people
  class Tracker < Events
    # An instance of Mixpanel::People. Use this to
    # send profile updates
    attr_reader :people

    # Takes your Mixpanel project token, as a string.
    #
    #    tracker = Mixpanel::Tracker.new(YOUR_MIXPANEL_TOKEN)
    #
    # By default, the tracker will send an message to Mixpanel
    # synchronously with each call, using an instance of Mixpanel::Consumer.
    #
    # You can also provide a block to the constructor
    # to specify particular consumer behaviors (for
    # example, if you wanted to write your messages to
    # a queue instead of sending them directly to Mixpanel)
    #
    #    tracker = Mixpanel::Tracker.new(YOUR_MIXPANEL_TOKEN) do |type, message|
    #        @kestrel.set(MY_MIXPANEL_QUEUE, [type,message].to_json)
    #    end
    #
    # If a block is provided, it is passed a type (one of :event or :profile_update)
    # and a string message. This same format is accepted by Mixpanel::Consumer#send!
    # and Mixpanel::BufferedConsumer#send!
    def initialize(token, &block)
      super(token, &block)
      @token = token
      @people = People.new(token, &block)
    end

    # A call to #track is a report that an event has occurred.  #track
    # takes a distinct_id representing the source of that event (for
    # example, a user id), an event name describing the event, and a
    # set of properties describing that event. Properties are provided
    # as a Hash with string keys and strings, numbers or booleans as
    # values.
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
      # This is here strictly to allow rdoc to include the relevant
      # documentation
      super
    end

    # A call to #import is to import an event occurred in the past. #import
    # takes a distinct_id representing the source of that event (for
    # example, a user id), an event name describing the event, and a
    # set of properties describing that event. Properties are provided
    # as a Hash with string keys and strings, numbers or booleans as
    # values.
    #
    #     tracker = Mixpanel::Tracker.new
    #
    #     # Import event that user "12345"'s credit card was declined
    #     tracker.import("API_KEY", "12345", "Credit Card Declined", {
    #       'time' => 1310111365
    #     })
    #
    #     # Properties describe the circumstances of the event,
    #     # or aspects of the source or user associated with the event
    #     tracker.import("API_KEY", "12345", "Welcome Email Sent", {
    #         'Email Template' => 'Pretty Pink Welcome',
    #         'User Sign-up Cohort' => 'July 2013',
    #         'time' => 1310111365
    #     })
    def import(api_key, distinct_id, event, properties={}, ip=nil)
      # This is here strictly to allow rdoc to include the relevant
      # documentation
      super
    end

    # Creates a distinct_id alias. \Events and updates with an alias
    # will be considered by mixpanel to have the same source, and
    # refer to the same profile.
    #
    # Multiple aliases can map to the same real_id, once a real_id is
    # used to track events or send updates, it should never be used as
    # an alias itself.
    #
    # Alias requests are always sent synchronously, directly to
    # the \Mixpanel service, regardless of how the tracker is configured.
    def alias(alias_id, real_id, events_endpoint=nil)
      consumer = Mixpanel::Consumer.new(events_endpoint)
      data = {
        'event' => '$create_alias',
        'properties' => {
          'distinct_id' => real_id,
          'alias' => alias_id,
          'token' => @token,
        }
      }

      message = {'data' => data}

      consumer.send!(:event, message.to_json)
    end
  end
end
