require 'mixpanel-ruby/events.rb'
require 'mixpanel-ruby/people.rb'

module Mixpanel
  # Use Mixpanel::Tracker to track events and profile updates in your application.
  # To track an event, call
  #
  #     tracker = Mixpanel::Tracker.new(YOUR_MIXPANEL_TOKEN)
  #     Mixpanel::Tracker.track(a_distinct_id, an_event_name, { properties })
  #
  # To send people updates, call
  #
  #     tracker = Mixpanel::Tracker.new(YOUR_MIXPANEL_TOKEN)
  #     tracker.people.set(a_distinct_id, { properties })
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
    # and a string message. This same format is accepted by Mixpanel::Consumer#send
    # and Mixpanel::BufferedConsumer#send
    def initialize(token, &block)
      super(token, &block)
      @people = People.new(token, &block)
    end


    # Creates a distinct_id alias. \Events and updates with an alias
    # will be considered by mixpanel to have the same source, and
    # refer to the same profile.
    #
    # Multiple aliases can map to the same real_id, once a real_id is
    # used to track events or send updates, it should never be used as
    # an alias itself.
    def alias(alias_id, real_id)
      track(real_id, '$create_alias', {
          'alias' => alias_id
      })
    end
  end
end
