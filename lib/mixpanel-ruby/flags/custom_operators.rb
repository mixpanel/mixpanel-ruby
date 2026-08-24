require 'time'
require 'json_logic'
require 'semantic_range'

module Mixpanel
  module Flags
    module CustomOperators
      # Using the official semantic versioning 2.0.0 regular expression to handle cross-platform validation
      # differences on other SDK's. For example, some platforms allow leading zeros even though it is not valid
      # as part of the Semver 2.0.0 spec. See https://semver.org/
      SEMVER_STRICT = /\A(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-((?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)(?:\.(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?(?:\+([0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*))?\z/

      # Strict RFC3339 guard for datetime strings.
      RFC3339_STRICT = /\A\d{4}-\d{2}-\d{2}[Tt]\d{2}:\d{2}:\d{2}(\.\d+)?([Zz]|[+-]\d{2}:\d{2})\z/

      # SemVer 2.0.0 requires major.minor.patch; partial versions are zero-padded to this.
      SEMVER_PARTS = 3

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

        actual_version = normalize_semver(actual)
        target_version = normalize_semver(target)
        return false unless actual_version.match?(SEMVER_STRICT) && target_version.match?(SEMVER_STRICT)

        cmp = SemanticRange.compare(actual_version, target_version)
        comparator_matches?(cmp, symbol)
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
        when '=' then cmp.zero?
        when '!=' then !cmp.zero?
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

      def convert_rfc3339_to_unix_seconds(value)
        return nil unless value.is_a?(String)

        normalized = value.strip.upcase
        return nil unless normalized =~ RFC3339_STRICT

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
