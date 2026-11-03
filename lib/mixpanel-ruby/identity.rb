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
  # Which combinations are valid depends on the project, so the tracker
  # rather than this class decides. On a hierarchical groups project the
  # company is part of the user's identity: a $user_id sent without a
  # $company_id resolves to a different user that nothing reconciles later,
  # so the tracker rejects it. A user who belongs to two companies is two
  # users, by design.
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

    # nil leaves a value unset; an empty string is a caller error rather
    # than an absent value. At least one value is required.
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
    def to_properties
      properties = {}
      properties['distinct_id'] = @distinct_id unless @distinct_id.nil?
      properties['$user_id'] = @user_id unless @user_id.nil?
      properties['$company_id'] = @company_id unless @company_id.nil?
      properties['$device_id'] = @device_id unless @device_id.nil?
      properties
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
      if value.respond_to?(:empty?) && value.empty?
        raise ArgumentError, "#{name} must be non-empty"
      end
      value.is_a?(String) ? value.dup.freeze : value
    end
  end

  # Validation shared by Events, People and Groups for hierarchical groups
  # projects. Not part of the public API.
  module HierarchicalGroups # :nodoc:
    # The operations /groups supports. A hierarchical groups user profile is a
    # group profile keyed by $user_id, so it supports the same set.
    GROUP_OPERATIONS = %w[$set $set_once $unset $union $remove $delete].freeze

    # Profile operations the HTTP API defines. Keys of a generic update message
    # that are in this list but not in GROUP_OPERATIONS are unsupported on /groups.
    KNOWN_OPERATIONS = (GROUP_OPERATIONS + %w[$add $append $merge]).freeze

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

    # The unsupported operations a generic update message carries.
    def unsupported_operations(message)
      message.keys.map(&:to_s) & (KNOWN_OPERATIONS - GROUP_OPERATIONS)
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
      # The company is part of a hierarchical user's identity, not a one-time
      # association. A $user_id sent without one resolves to a separate user
      # that nothing reconciles later. A device id rescues that case: Mixpanel
      # ignores the user id, keeps the event under the device, and links it to
      # the company-scoped user once a later event carries all three.
      if hierarchical_groups && identity.user_id && identity.company_id.nil? && identity.device_id.nil?
        raise ArgumentError, "#{identity} needs a company on a hierarchical groups project. " \
          'A user id sent without one, and without a device id, names a separate user that cannot ' \
          'be merged afterwards.'
      end
    end

    def require_company_id(company_id)
      if company_id.nil? || (company_id.respond_to?(:empty?) && company_id.empty?)
        raise ArgumentError, 'company_id must be non-empty'
      end
    end
  end
end
