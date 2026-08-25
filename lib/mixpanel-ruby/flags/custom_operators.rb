require 'date'
require 'time'
require 'json_logic'

module Mixpanel
  module Flags
    module CustomOperators
      # Using the official semantic versioning 2.0.0 regular expression to handle cross-platform validation
      # differences on other SDK's. For example, some platforms allow leading zeros even though it is not valid
      # as part of the Semver 2.0.0 spec. See https://semver.org/
      SEMVER_STRICT = /\A(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-((?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)(?:\.(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?(?:\+([0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*))?\z/

      # Strict RFC3339 guard for datetime strings. The date and hour fields are captured so the
      # calendar can be validated separately; the pattern only constrains their shape.
      RFC3339_STRICT = /\A(\d{4})-(\d{2})-(\d{2})[Tt](\d{2}):\d{2}:\d{2}(\.\d+)?([Zz]|[+-]\d{2}:\d{2})\z/

      # SemVer 2.0.0 requires major.minor.patch; partial versions are zero-padded to this.
      SEMVER_PARTS = 3

      # Longest operand the semver regex is allowed to see. A real version never approaches this; the
      # bound matches MAX_LENGTH in node-semver, and keeps an arbitrarily long property value off the
      # regex regardless of how the engine schedules backtracking.
      MAX_SEMVER_LENGTH = 256

      # Epoch milliseconds are compared as int64 elsewhere, so anything at or beyond this is out of range.
      MAX_EPOCH_MS = 2**63

      module_function

      # Implements a custom operation for semantic versioning comparison that conforms to the
      # semver 2.0.0 standard. Prior to comparison, any leading version prefix is stripped.
      def semver_compare(values)
        unpacked = operands(values)
        return false unless unpacked

        actual, symbol, target = unpacked
        return false unless actual.is_a?(String) && target.is_a?(String)
        return false if actual.length > MAX_SEMVER_LENGTH || target.length > MAX_SEMVER_LENGTH

        actual_version = normalize_semver(actual)
        target_version = normalize_semver(target)
        return false unless actual_version.match?(SEMVER_STRICT) && target_version.match?(SEMVER_STRICT)

        cmp = compare_semver(actual_version, target_version)
        comparator_matches?(cmp, symbol)
      end

      # Strip optional build metadata and separate the core version from pre-release identifiers
      def split_semver(version)
        plus = version.index('+')
        version = version[0, plus] if plus
        dash = version.index('-')
        return [version.split('.'), []] unless dash

        [version[0, dash].split('.'), version[(dash + 1)..-1].split('.')]
      end

      def numeric_identifier?(identifier)
        identifier.match?(/\A[0-9]+\z/)
      end

      # Numeric identifiers carry no leading zeros, so the longer run of digits is the larger number.
      # Comparing them as digits rather than parsing to a fixed-width integer keeps versions that
      # overflow a 64-bit integer ordered correctly.
      def compare_numeric(a, b)
        return a.length <=> b.length unless a.length == b.length

        a <=> b
      end

      # SemVer 2.0.0 section 11.4: digits compare numerically, a numeric identifier ranks below an
      # alphanumeric one, and anything else compares by ASCII order.
      def compare_prerelease_identifier(a, b)
        a_numeric = numeric_identifier?(a)
        b_numeric = numeric_identifier?(b)
        return compare_numeric(a, b) if a_numeric && b_numeric
        return -1 if a_numeric
        return 1 if b_numeric

        a <=> b
      end

      # Ordering per SemVer 2.0.0 section 11. Both operands have already been normalized and matched
      # against the official regex, so the core holds exactly three numeric identifiers and every
      # prerelease field is well-formed; the split needs no error path.
      def compare_semver(actual, target)
        actual_core, actual_prerelease = split_semver(actual)
        target_core, target_prerelease = split_semver(target)

        actual_core.each_with_index do |part, index|
          result = compare_numeric(part, target_core[index])
          return result unless result.zero?
        end

        # A prerelease ranks below the release it belongs to (section 11.3).
        return 0 if actual_prerelease.empty? && target_prerelease.empty?
        return 1 if actual_prerelease.empty?
        return -1 if target_prerelease.empty?

        [actual_prerelease.length, target_prerelease.length].min.times do |index|
          result = compare_prerelease_identifier(actual_prerelease[index], target_prerelease[index])
          return result unless result.zero?
        end
        # Every field so far is equal, so the longer list wins (section 11.4.4).
        actual_prerelease.length <=> target_prerelease.length
      end

      # Implements a custom operation for datetime comparison. The target value stored on the
      # feature flag is the millisecond epoch, whereas the actual value provided at evaluation
      # time must be RFC-3339 formatted.
      def datetime_compare(values)
        unpacked = operands(values)
        return false unless unpacked

        actual, symbol, target = unpacked
        actual_sec = convert_rfc3339_to_unix_seconds(actual)
        target_sec = convert_unix_milliseconds_to_seconds(target)
        return false unless actual_sec && target_sec

        cmp = actual_sec - target_sec
        comparator_matches?(cmp, symbol)
      end

      def operands(values)
        return nil unless values.length == 3

        actual, symbol, target = values
        return nil unless symbol.is_a?(String)

        [actual, symbol, target]
      end

      def comparator_matches?(cmp, symbol)
        case symbol
        when '===' then cmp.zero?
        when '!==' then !cmp.zero?
        when '<' then cmp < 0
        when '<=' then cmp <= 0
        when '>' then cmp > 0
        when '>=' then cmp >= 0
        else false
        end
      end

      def normalize_semver(str)
        stripped = str.strip
        stripped = stripped[1..] if stripped =~ /\Av/i

        suffix_start = stripped.length
        ['-', '+'].each do |separator|
          index = stripped.index(separator)
          suffix_start = index if index && index < suffix_start
        end

        core = stripped[0, suffix_start]
        suffix = stripped[suffix_start..] || ''

        # split(-1) keeps trailing empty fields, so "1." and "1.2.3." stay malformed instead of
        # silently padding to a valid version. Returning the input unchanged lets the validator reject it.
        segments = core.split('.', -1)
        return stripped unless segments.length.between?(1, SEMVER_PARTS) && segments.all? { |seg| seg.match?(/\A\d+\z/) }

        segments += ['0'] * (SEMVER_PARTS - segments.length)
        segments.join('.') + suffix
      end

      # The pattern constrains each field to two digits, which still admits a date that cannot exist,
      # such as 2026-02-30 or 29 February in a common year. Time.iso8601 rolls those forward into a
      # real instant instead of raising, and hour 24 likewise becomes the following midnight, so the
      # calendar is checked here. RFC 3339 section 5.6 allows hours 00 through 23.
      def real_calendar_date?(year, month, day, hour)
        hour <= 23 && Date.valid_date?(year, month, day)
      end

      def convert_rfc3339_to_unix_seconds(value)
        return nil unless value.is_a?(String)

        normalized = value.strip.upcase
        fields = RFC3339_STRICT.match(normalized)
        return nil unless fields
        return nil unless real_calendar_date?(fields[1].to_i, fields[2].to_i, fields[3].to_i, fields[4].to_i)

        parsed = Time.iso8601(normalized)
        parsed.to_i
      rescue ArgumentError
        nil
      end

      def convert_unix_milliseconds_to_seconds(value)
        return nil unless value.is_a?(Numeric)
        # A value int64 cannot represent is not a real timestamp; treating one as a bound would let a
        # nonsense target define a rollout window. NaN fails this comparison too.
        return nil unless value.abs < MAX_EPOCH_MS

        value.to_i.fdiv(1000).truncate
      end
    end
  end
end

JsonLogic.add_operation('semver_compare') do |values, _data|
  Mixpanel::Flags::CustomOperators.semver_compare(values)
end

JsonLogic.add_operation('datetime_compare') do |values, _data|
  Mixpanel::Flags::CustomOperators.datetime_compare(values)
end
