require 'date'
require 'json'
require 'time'

require 'mixpanel-ruby/consumer'
require 'mixpanel-ruby/error'
require 'mixpanel-ruby/identity'
require 'mixpanel-ruby/groups'

module Mixpanel

  # Handles formatting Mixpanel profile updates and
  # sending them to the consumer. You will rarely need
  # to instantiate this class directly- to send
  # profile updates, use Mixpanel::Tracker#people
  #
  #     tracker = Mixpanel::Tracker.new(YOUR_MIXPANEL_TOKEN)
  #     tracker.people.set(...) # Or .append(..), or track_charge(...) etc.
  #
  # == Hierarchical groups
  #
  # On a hierarchical groups tracker (Tracker.new(token, hierarchical_groups: true))
  # user profiles are group profiles keyed by $user_id, so they support only what
  # /groups supports: #set, #set_once, #unset, #union and #delete_user.
  # #increment, #plus_one, #append, #track_charge and #clear_charges raise
  # Mixpanel::UnsupportedOperationError, as does #update with a $add, $append or
  # $merge operation.
  #
  # Every user profile update on a hierarchical groups tracker goes to the
  # $user_id group profile within a company, through /groups. Nothing is sent
  # to /engage. Name the user and company with a Mixpanel::Identity in place
  # of distinct_id:
  #
  #     tracker.people.set(Mixpanel::Identity.new(user_id: '12345', company_id: 'acme'), {
  #         'role' => 'admin'
  #     })
  #
  # The company comes from the identity, or else a $company_id in
  # optional_params, so these updates do not need Tracker#for_company. On a
  # tracker bound with #for_company, a user from another company raises
  # ArgumentError and sends nothing.
  #
  # A distinct id, as a string or as an identity's distinct_id, must be one
  # Mixpanel built, of the form <tt>$company:{company}|$user:{user}</tt>. It
  # sends the same update as the identity with that user and company. Any
  # other distinct id raises ArgumentError and sends nothing, as does #update
  # with any other $distinct_id.
  #
  # Without hierarchical groups, a distinct id or an identity with a
  # distinct_id updates that profile through /engage.
  class People

    # You likely won't need to instantiate instances of Mixpanel::People
    # directly. The best way to get an instance of Mixpanel::People is
    #
    #     tracker = Mixpanel::Tracker.new(YOUR_MIXPANEL_TOKEN)
    #     tracker.people # An instance of Mixpanel::People
    #
    def initialize(token, error_handler=nil, hierarchical_groups: false, company_id: nil, &block)
      @token = token
      @error_handler = error_handler || ErrorHandler.new
      @hierarchical_groups = hierarchical_groups ? true : false
      @company_id = company_id

      if block
        @sink = block
      else
        consumer = Consumer.new
        @sink = consumer.method(:send!)
      end

      # Hierarchical groups user profiles are sent to /groups through the same sink.
      @user_profiles = Groups.new(token, @error_handler, hierarchical_groups: @hierarchical_groups, &@sink)
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
      profile_update(distinct_id, '$set', properties, ip, optional_params)
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
      profile_update(distinct_id, '$set_once', properties, ip, optional_params)
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
      refuse_engage_only_operation(distinct_id, '$add', 'increment')
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
      refuse_engage_only_operation(distinct_id, '$append', 'append')
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
      profile_update(distinct_id, '$union', properties, ip, optional_params)
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
      profile_update(distinct_id, '$unset', properties, ip, optional_params)
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
    #
    # On a hierarchical groups tracker, raises Mixpanel::UnsupportedOperationError,
    # since #track_charge is not supported there.
    def clear_charges(distinct_id, ip=nil, optional_params={})
      if @hierarchical_groups
        raise UnsupportedOperationError, 'clear_charges is not supported for hierarchical groups projects, ' \
          "which can't track_charge."
      end
      unset(distinct_id, '$transactions', ip, optional_params)
    end

    # Permanently delete a profile from \Mixpanel people analytics
    # To delete a user and ignore alias pass into optional params
    #   {"$ignore_alias"=>true}
    #
    # Like #set, accepts a Mixpanel::Identity in place of distinct_id.
    def delete_user(distinct_id, optional_params={})
      profile_update(distinct_id, '$delete', '', nil, optional_params)
    end

    # Send a generic update to \Mixpanel people analytics.
    # Caller is responsible for formatting the update message, as
    # documented in the \Mixpanel HTTP specification, and passing
    # the message as a dict to #update. This
    # method might be useful if you want to use very new
    # or experimental features of people analytics from Ruby
    # The \Mixpanel HTTP tracking API is documented at
    # https://mixpanel.com/help/reference/http
    #
    # On a hierarchical groups tracker, raises Mixpanel::UnsupportedOperationError
    # if the message carries $add, $append or $merge. Otherwise the message's
    # $distinct_id must be of the form <tt>$company:{company}|$user:{user}</tt>,
    # or ArgumentError is raised. The message is sent to /groups with
    # $distinct_id replaced by the $user_id group profile and company it names.
    def update(message)
      if @hierarchical_groups
        unsupported = HierarchicalGroups.unsupported_operations(message)
        raise_unsupported_operation(unsupported.first) unless unsupported.empty?
        return user_group_message_update(message)
      end

      data = {
        '$token' => @token,
        '$time' =>  (Time.now.to_f * 1000).to_i,
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

    # Returns a Mixpanel::People that refuses user profile updates for any
    # company other than company_id, sharing this instance's consumer and
    # error handler. The receiver is unchanged. Tracker#for_company uses it.
    def for_company(company_id) # :nodoc:
      People.new(@token, @error_handler, hierarchical_groups: @hierarchical_groups, company_id: company_id, &@sink)
    end

    private

    # Sends a supported profile operation for a distinct id or a Mixpanel::Identity.
    def profile_update(distinct_id, operation, properties, ip, optional_params)
      if distinct_id.is_a?(Identity)
        identity = distinct_id
        HierarchicalGroups.require_identity_matches_project(identity, @hierarchical_groups)
        unless identity.distinct_id.nil?
          return profile_update(identity.distinct_id, operation, properties, ip, optional_params)
        end
        return user_group_update(identity, operation, properties, ip, optional_params)
      end

      if @hierarchical_groups
        company_id, user_id = HierarchicalGroups.require_combined_distinct_id(distinct_id)
        identity = Identity.new(user_id: user_id, company_id: company_id)
        return user_group_update(identity, operation, properties, ip, optional_params)
      end

      message = {
        '$distinct_id' => distinct_id,
        operation => properties,
      }.merge(optional_params)
      message['$ip'] = ip if ip

      update(message)
    end

    # A hierarchical groups user profile is the $user_id group profile within
    # the identity's company.
    def user_group_update(identity, operation, properties, ip, optional_params)
      unless @hierarchical_groups
        raise ArgumentError, "#{identity} cannot identify a profile on this project. " \
          'User profiles are addressed by distinct id unless the project uses hierarchical groups.'
      end
      if identity.user_id.nil?
        if identity.company_id.nil?
          raise ArgumentError, "#{identity} names no user, so it cannot identify a profile. " \
            'Device ids identify anonymous events, not profiles.'
        end
        raise ArgumentError, "User profile updates require a user id, and #{identity} has none. " \
          'Use tracker.for_company(company_id).company.set(properties) ' \
          "to update the company's profile."
      end
      require_bound_company(identity.company_id, identity.to_s)

      message = {
        '$group_key' => HierarchicalGroups::USER_ID_GROUP_KEY,
        '$group_id' => identity.user_id,
        operation => properties,
      }.merge(optional_params)
      message['$ip'] = ip if ip
      # The identity's company wins over a $company_id in optional_params. With
      # neither, Groups#update raises Mixpanel::CompanyRequiredError.
      message['$company_id'] = identity.company_id unless identity.company_id.nil?

      @user_profiles.update(message)
    end

    # A tracker bound with Tracker#for_company refuses a user from another
    # company rather than silently updating that company's profile.
    def require_bound_company(company_id, described)
      return if company_id.nil? || @company_id.nil? || company_id == @company_id

      raise ArgumentError, "This tracker is bound to company #{@company_id.inspect}, but #{described} " \
        "belongs to company #{company_id.inspect}. Update the user through a tracker for that " \
        'company, or one without for_company.'
    end

    # Sends a generic update message to the $user_id group profile its
    # combined $distinct_id names.
    def user_group_message_update(message)
      company_id, user_id = HierarchicalGroups.require_combined_distinct_id(message['$distinct_id'])
      require_bound_company(company_id, message['$distinct_id'].inspect)
      group_message = message.reject { |key, _| key.to_s == '$distinct_id' }
      group_message['$group_key'] = HierarchicalGroups::USER_ID_GROUP_KEY
      group_message['$group_id'] = user_id
      group_message['$company_id'] = company_id

      @user_profiles.update(group_message)
    end

    # $add and $append exist only on /engage, so these have no hierarchical
    # groups equivalent and no Mixpanel::Identity form.
    def refuse_engage_only_operation(distinct_id, operation, method_name)
      raise_unsupported_operation(operation) if @hierarchical_groups
      if distinct_id.is_a?(Identity)
        raise ArgumentError, "#{method_name} does not accept a Mixpanel::Identity; pass a distinct id"
      end
    end

    def raise_unsupported_operation(operation)
      raise UnsupportedOperationError, "#{operation} is not supported for hierarchical groups projects, " \
        'whose user profiles are group profiles keyed by $user_id. Supported operations are ' \
        "#{HierarchicalGroups::GROUP_OPERATIONS.join(', ')}, so increment, plus_one, append and " \
        'track_charge have no hierarchical groups equivalent.'
    end

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
