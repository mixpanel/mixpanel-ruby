require 'mixpanel-ruby/error'

module Mixpanel

  # Identifies who an event or profile update belongs to.
  #
  # Mixpanel resolves an identity from whichever of distinct_id, $user_id,
  # $company_id and $device_id an event carries, so an Identity sets any
  # combination of them and leaves the rest unset (nil).
  #
  #     Mixpanel::Identity.new(distinct_id: 'user_123')                       # a plain distinct id
  #     Mixpanel::Identity.new(user_id: 'user_123', device_id: 'device_abc')  # simplified id merge
  #     Mixpanel::Identity.new(user_id: 'user_123', company_id: 'acme')       # hierarchical groups
  #     Mixpanel::Identity.new(device_id: 'device_abc')                       # anonymous, no user yet
  #     Mixpanel::Identity.new(company_id: 'acme')                            # a company, no user
  #
  # Pass an Identity wherever Mixpanel::Tracker#track, #import, #import_events or
  # the supported Mixpanel::People methods accept a distinct_id.
  #
  # Which combinations are valid depends on the project, so the tracker rather
  # than this class decides. On a hierarchical groups project the company is
  # part of the user's identity: a $user_id sent without a $company_id
  # resolves to a different user that nothing reconciles later, so include the
  # company whenever the user has one. Events still send a user id without one
  # as given; user profile updates need the company. A user who belongs to two
  # companies is two users, by design.
  #
  # On a hierarchical groups project Mixpanel builds the distinct id from the
  # user and company, so a raw distinct_id names a different, unrelated user.
  # Set distinct_id only when it is one Mixpanel itself built, of the form
  # <tt>$company:{company}|$user:{user}</tt>. User profile updates there
  # require that form, and update the $user_id group profile it names.
  #
  # Instances are frozen.
  class Identity
    attr_reader :distinct_id, :user_id, :company_id, :device_id

    # Each id is a String or an Integer and is sent as given. nil leaves a
    # value unset; an empty string is a caller error rather than an absent
    # value, and any other type raises ArgumentError. At least one value is
    # required.
    def initialize(distinct_id: nil, user_id: nil, company_id: nil, device_id: nil)
      @distinct_id = check_value(distinct_id, 'distinct_id')
      @user_id = check_value(user_id, 'user_id')
      @company_id = check_value(company_id, 'company_id')
      @device_id = check_value(device_id, 'device_id')

      if @distinct_id.nil? && @user_id.nil? && @company_id.nil? && @device_id.nil?
        raise ArgumentError, 'An identity needs at least one of distinct_id, user_id, company_id or device_id'
      end

      freeze
    end

    # True if this identity names a company, which is what sends it down
    # Mixpanel's hierarchical groups resolution.
    def hierarchical?
      !@company_id.nil?
    end

    # The event properties this identity contributes, with unset values omitted.
    def to_properties # :nodoc:
      properties = {}
      properties['distinct_id'] = @distinct_id unless @distinct_id.nil?
      properties['$user_id'] = @user_id unless @user_id.nil?
      properties['$company_id'] = @company_id unless @company_id.nil?
      properties['$device_id'] = @device_id unless @device_id.nil?
      properties
    end

    # A feature flag evaluation context for this identity, so callers do not
    # hand-write reserved keys such as $company_id. The ids go under the keys
    # flags read, the groups at the top level and the custom properties under
    # custom_properties:
    #
    #     identity.to_flag_context(groups: { 'department' => 'finance' },
    #                              custom_properties: { 'plan' => 'enterprise' })
    #     # => { '$user_id' => 'user_123', '$company_id' => 'acme', 'department' => 'finance',
    #     #      'custom_properties' => { 'plan' => 'enterprise' } }
    def to_flag_context(groups: {}, custom_properties: {})
      context = groups.dup
      context['distinct_id'] = @distinct_id unless @distinct_id.nil?
      context['$user_id'] = @user_id unless @user_id.nil?
      context['$company_id'] = @company_id unless @company_id.nil?
      context['device_id'] = @device_id unless @device_id.nil?
      context['custom_properties'] = custom_properties.dup unless custom_properties.empty?
      context
    end

    def ==(other)
      other.is_a?(Identity) && state == other.state
    end
    alias eql? ==

    def hash
      state.hash
    end

    def to_s
      set = [['distinct_id', @distinct_id], ['user_id', @user_id],
             ['company_id', @company_id], ['device_id', @device_id]].reject { |_, value| value.nil? }
      "Mixpanel::Identity{#{set.map { |name, value| "#{name}=#{value}" }.join(', ')}}"
    end
    alias inspect to_s

    protected

    def state
      [@distinct_id, @user_id, @company_id, @device_id]
    end

    private

    def check_value(value, name)
      return nil if value.nil?
      HierarchicalGroups.require_id_type(value, name)
      if value.respond_to?(:empty?) && value.empty?
        raise ArgumentError, "#{name} must be non-empty"
      end
      value.is_a?(String) ? value.dup.freeze : value
    end
  end

  # The same class as Mixpanel::Identity, under the name the other Mixpanel
  # SDKs use.
  MixpanelIdentity = Identity

  # Validation shared by Events, People and Groups for hierarchical groups
  # projects. Not part of the public API.
  module HierarchicalGroups # :nodoc:
    # The operations /groups supports. A hierarchical groups user profile is a
    # group profile keyed by $user_id, so it supports the same set.
    GROUP_OPERATIONS = %w[$set $set_once $unset $union $remove $delete].freeze

    # Keys of a generic update message that are not operations.
    NON_OPERATION_KEYS = %w[
      $token $distinct_id $group_key $group_id $company_id $time $ip
      $ignore_time $ignore_alias $mp_metadata $latitude $longitude
    ].freeze

    USER_ID_GROUP_KEY = '$user_id'.freeze

    COMBINED_COMPANY_PREFIX = '$company:'.freeze
    COMBINED_USER_SEPARATOR = '|$user:'.freeze

    module_function

    # Parses a distinct id Mixpanel built, of the form
    # <tt>$company:{company}|$user:{user}</tt>, into [company_id, user_id].
    # The company ends at the first |$user: and the user is everything after
    # it. Returns nil unless both parts are non-empty.
    def parse_combined_distinct_id(distinct_id)
      return nil unless distinct_id.is_a?(String) && distinct_id.start_with?(COMBINED_COMPANY_PREFIX)
      separator = distinct_id.index(COMBINED_USER_SEPARATOR, COMBINED_COMPANY_PREFIX.length)
      return nil if separator.nil?
      company_id = distinct_id[COMBINED_COMPANY_PREFIX.length...separator]
      user_id = distinct_id[(separator + COMBINED_USER_SEPARATOR.length)..-1]
      return nil if company_id.empty? || user_id.empty?
      [company_id, user_id]
    end

    # The [company_id, user_id] a hierarchical groups user profile update
    # addresses by distinct id. User profiles on these projects are group
    # profiles that need both a user and a company, so anything but a combined
    # distinct id raises ArgumentError.
    def require_combined_distinct_id(distinct_id)
      parsed = parse_combined_distinct_id(distinct_id)
      return parsed unless parsed.nil?
      raise ArgumentError, 'User profile updates on hierarchical groups projects need a user and a company, ' \
        "and distinct id #{distinct_id.inspect} does not name both. Pass " \
        'Mixpanel::Identity.new(user_id: user_id, company_id: company_id) or a distinct id of the form ' \
        '$company:{company}|$user:{user}.'
    end

    # The unsupported operations a generic update message carries: any
    # $-prefixed key that is neither a /groups operation nor a non-operation
    # key such as $token or $company_id.
    def unsupported_operations(message)
      message.keys.map(&:to_s).select do |key|
        key.start_with?('$') && !GROUP_OPERATIONS.include?(key) && !NON_OPERATION_KEYS.include?(key)
      end
    end

    # Ids are Strings or Integers. Anything else raises ArgumentError.
    def require_id_type(value, name)
      return if value.is_a?(String) || value.is_a?(Integer)
      raise ArgumentError, "#{name} must be a String or an Integer, not #{value.inspect}"
    end

    # A bound company and an identity's company are the same company when
    # they are equal as strings, so 7 and '7' match.
    def same_company?(a, b)
      a.to_s == b.to_s
    end

    # Hierarchical groups is a project setting, so a hierarchical identity is
    # only valid on a tracker created for a hierarchical groups project.
    # Ingestion accepts the keys on any project but ignores them, so a mismatch
    # would be silently mis-attributed.
    def require_identity_matches_project(identity, hierarchical_groups)
      if identity.nil?
        raise ArgumentError, 'identity must be non-nil'
      end
      if identity.hierarchical? && !hierarchical_groups
        raise ArgumentError, "#{identity} requires a hierarchical groups tracker: " \
          'Mixpanel::Tracker.new(token, hierarchical_groups: true)'
      end
    end

    def require_company_id(company_id)
      if company_id.nil? || (company_id.respond_to?(:empty?) && company_id.empty?)
        raise ArgumentError, 'company_id must be non-empty'
      end
      require_id_type(company_id, 'company_id')
    end
  end
end
