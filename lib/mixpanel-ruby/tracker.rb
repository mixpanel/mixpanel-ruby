require 'mixpanel-ruby/events.rb'
require 'mixpanel-ruby/people.rb'
require 'mixpanel-ruby/groups.rb'
require 'mixpanel-ruby/flags/local_flags_provider.rb'
require 'mixpanel-ruby/flags/remote_flags_provider.rb'

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
  # To send groups updates, call
  #
  #     tracker = Mixpanel::Tracker.new(YOUR_MIXPANEL_TOKEN)
  #     tracker.groups.set(group_key, group_id, {properties})
  #
  # You can find your project token in the settings dialog for your
  # project, inside of the Mixpanel web application.
  #
  # Mixpanel::Tracker is a subclass of Mixpanel::Events, and exposes
  # an instance of Mixpanel::People as Tracker#people
  # and an instance of Mixpanel::Groups as Tracker#groups
  class Tracker < Events
    # An instance of Mixpanel::People. Use this to
    # send profile updates
    attr_reader :people

    # An instance of Mixpanel::Groups. Use this to send groups updates
    attr_reader :groups

    # An instance of Mixpanel::Flags::LocalFlagsProvider. Use this for
    # client-side feature flag evaluation
    attr_reader :local_flags

    # An instance of Mixpanel::Flags::RemoteFlagsProvider. Use this for
    # server-side feature flag evaluation
    attr_reader :remote_flags

    # The company this tracker is bound to by #for_company, or nil.
    attr_reader :company_id

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
    #
    # Optional parameters:
    # - credentials: ServiceAccountCredentials for authentication (used for import and feature flags)
    # - local_flags_config: Configuration hash for local feature flags
    # - remote_flags_config: Configuration hash for remote feature flags
    # - hierarchical_groups: true if the project uses hierarchical groups
    #   (default false). This only adds validation; a message that is valid
    #   either way is sent unchanged. Feature flag exposure events are the
    #   exception: they are attributed by $user_id and $company_id from the
    #   flag context.
    #
    # == Hierarchical groups
    #
    # On a hierarchical groups project Mixpanel builds the distinct id from
    # $user_id and $company_id. Identify events and user profiles with a
    # Mixpanel::Identity, and send group profile updates through #for_company:
    #
    #    tracker = Mixpanel::Tracker.new(YOUR_MIXPANEL_TOKEN, hierarchical_groups: true)
    #    user = Mixpanel::Identity.new(user_id: 'user_123', company_id: 'acme')
    #
    #    tracker.track(user, 'Signup')
    #    tracker.people.set(user, {'role' => 'admin'})
    #    tracker.for_company('acme').groups.set('$company_id', 'acme', {'tier' => 'enterprise'})
    #
    # Events still accept a string distinct id and never refuse one, but one
    # that is not of the form <tt>$company:{company}|$user:{user}</tt> names a
    # separate user that nothing reconciles later. User profile updates never
    # go to /engage: they accept only an identity with a user and company, or
    # a distinct id of that form, and raise ArgumentError for any other. User
    # profiles support only set, set_once, unset, union and delete_user; see
    # Mixpanel::People.
    #
    # Mistakes in the calling code raise ArgumentError,
    # Mixpanel::UnsupportedOperationError or Mixpanel::CompanyRequiredError
    # directly; they are not passed to the error handler.
    def initialize(token, error_handler=nil, credentials: nil, local_flags_config: nil, remote_flags_config: nil, hierarchical_groups: false, &block)
      super(token, error_handler, credentials: credentials, hierarchical_groups: hierarchical_groups, &block)

      @people = People.new(token, error_handler, hierarchical_groups: hierarchical_groups, &block)
      @groups = Groups.new(token, error_handler, hierarchical_groups: hierarchical_groups, &block)

      # Initialize local flags if config provided
      if local_flags_config
        @local_flags = Flags::LocalFlagsProvider.new(
          token,
          local_flags_config,
          method(:track),  # Pass bound method as callback
          error_handler || ErrorHandler.new,
          credentials,
          hierarchical_groups: hierarchical_groups
        )
      end

      # Initialize remote flags if config provided
      if remote_flags_config
        @remote_flags = Flags::RemoteFlagsProvider.new(
          token,
          remote_flags_config,
          method(:track),  # Pass bound method as callback
          error_handler || ErrorHandler.new,
          credentials,
          hierarchical_groups: hierarchical_groups
        )
      end
    end

    # A call to #track is a report that an event has occurred.  #track
    # takes a distinct_id representing the source of that event (for
    # example, a user id), an event name describing the event, and a
    # set of properties describing that event. Properties are provided
    # as a Hash with string keys and strings, numbers or booleans as
    # values.
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
    #
    # distinct_id may also be a Mixpanel::Identity, whose keys replace any
    # caller-supplied values for the same keys in properties:
    #
    #     tracker.track(Mixpanel::Identity.new(user_id: '12345', company_id: 'acme'), 'Signup')
    #
    # Raises ArgumentError if the identity does not match the project, for
    # example an identity with a company on a tracker created without
    # hierarchical_groups: true.
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
    #     tracker = Mixpanel::Tracker.new(YOUR_MIXPANEL_TOKEN)
    #
    #     # Using deprecated API key (still supported)
    #     tracker.import("API_KEY", "12345", "Credit Card Declined", {
    #       'time' => 1310111365
    #     })
    #
    #     # Using service account credentials (recommended)
    #     credentials = Mixpanel::ServiceAccountCredentials.new(username, secret, project_id)
    #     tracker = Mixpanel::Tracker.new(YOUR_MIXPANEL_TOKEN, credentials: credentials)
    #     tracker.import(nil, "12345", "Welcome Email Sent", {
    #         'Email Template' => 'Pretty Pink Welcome',
    #         'User Sign-up Cohort' => 'July 2013',
    #         'time' => 1310111365
    #     })
    #
    # Like #track, distinct_id may be a Mixpanel::Identity.
    def import(api_key, distinct_id, event, properties={}, ip=nil)
      # This is here strictly to allow rdoc to include the relevant
      # documentation
      super
    end

    # Import an event using service account credentials from the constructor.
    # This is the recommended method for importing historical events with service accounts.
    #
    # Service account credentials must be provided when creating the Tracker.
    # This method provides a cleaner API than import() as it doesn't require
    # passing nil as the first parameter.
    #
    #     credentials = Mixpanel::ServiceAccountCredentials.new(username, secret, project_id)
    #     tracker = Mixpanel::Tracker.new(YOUR_MIXPANEL_TOKEN, credentials: credentials)
    #
    #     # Import a historical event
    #     tracker.import_events('user123', 'Past Event', {
    #         'Email Template' => 'Welcome Email',
    #         'time' => 1369353600
    #     })
    #
    # Like #track, distinct_id may be a Mixpanel::Identity.
    def import_events(distinct_id, event, properties={}, ip=nil)
      # This is here strictly to allow rdoc to include the relevant
      # documentation
      super
    end

    # Returns a new Tracker bound to the given company. Its #groups add a
    # top-level $company_id to every group profile update, replacing any
    # $company_id in optional_params:
    #
    #    acme = tracker.for_company('acme')
    #    acme.groups.set('$company_id', 'acme', company_properties)
    #    acme.groups.set('$user_id', 'user_123', user_properties)
    #    acme.groups.set('department', 'finance', department_properties)
    #
    # The returned tracker shares this tracker's consumer, error handler and
    # feature flag providers, and this tracker is unchanged. Events and user
    # profile updates are not affected: a Mixpanel::Identity carries its own
    # company. Available on any tracker, but only hierarchical groups
    # projects need it.
    #
    # Raises ArgumentError if company_id is nil or empty.
    def for_company(company_id)
      bound_groups = @groups.for_company(company_id)
      view = dup
      view.bind_company(company_id, bound_groups)
      view
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
    #
    # On a hierarchical groups tracker, raises Mixpanel::UnsupportedOperationError
    # before anything is sent.
    def alias(alias_id, real_id, events_endpoint=nil)
      if @hierarchical_groups
        raise UnsupportedOperationError, 'alias is not supported for hierarchical groups projects, ' \
          'which identify a user by company and user id. Track with a ' \
          'Mixpanel::Identity.new(user_id: ..., company_id: ...) instead.'
      end
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

      ret = true
      begin
        consumer.send!(:event, message.to_json)
      rescue MixpanelError => e
        @error_handler.handle(e)
        ret = false
      end

      ret
    end

    # A call to #generate_tracking_url will return a formatted url for
    # pixel based tracking.  #generate_tracking_url takes a distinct_id
    # representing the source of that event (for example, a user id),
    # an event name describing the event, and a set of properties describing
    # that event. Properties are provided as a Hash with string keys and
    # strings, numbers or booleans as values. For more information, please see:
    # https://mixpanel.com/docs/api-documentation/pixel-based-event-tracking
    #
    #     tracker = Mixpanel::Tracker.new(YOUR_MIXPANEL_TOKEN)
    #
    #     # generate pixel tracking url in order to track that user
    #     # "12345"'s credit card was declined
    #     url = tracker.generate_tracking_url("12345", "Credit Card Declined", {
    #       'time' => 1310111365
    #     })
    #
    #     url == 'https://api.mixpanel.com/track/?data=[BASE_64_JSON_EVENT]&ip=1&img=1'
    def generate_tracking_url(distinct_id, event, properties={}, endpoint=nil)
      properties = {
        'distinct_id' => distinct_id,
        'token' => @token,
        'time' => (Time.now.to_f * 1000).to_i,
        'mp_lib' => 'ruby',
        '$lib_version' => Mixpanel::VERSION,
      }.merge(properties)

      raw_data = {
        'event' => event,
        'properties' => properties,
      }

      endpoint = endpoint || 'https://api.mixpanel.com/track/'
      data = Base64.urlsafe_encode64(raw_data.to_json)

      "#{endpoint}?data=#{data}&ip=1&img=1"
    end

    protected

    def bind_company(company_id, groups)
      @company_id = company_id
      @groups = groups
    end
  end
end
