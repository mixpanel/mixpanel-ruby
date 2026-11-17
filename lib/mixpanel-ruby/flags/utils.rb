require 'securerandom'

module Mixpanel
  module Flags
    module Utils
      EXPOSURE_EVENT = '$experiment_started'.freeze

      # FNV-1a 64-bit hash implementation
      # Used for consistent variant assignment
      #
      # @param data [String] Data to hash
      # @return [Integer] 64-bit hash value
      def self.fnv1a_64(data)
        fnv_prime = 0x100000001b3
        hash_value = 0xcbf29ce484222325

        data.bytes.each do |byte|
          hash_value ^= byte
          hash_value *= fnv_prime
          hash_value &= 0xffffffffffffffff  # Keep 64-bit
        end

        hash_value
      end

      # Normalized hash for variant assignment
      # Returns a float in the range [0.0, 1.0) for rollout percentage matching
      #
      # @param key [String] Key to hash (typically distinct_id)
      # @param salt [String] Salt value (flag-specific)
      # @return [Float] Value between 0.0 and 1.0 (non-inclusive upper bound)
      def self.normalized_hash(key, salt)
        combined = key.to_s + salt.to_s
        hash_value = fnv1a_64(combined)
        (hash_value % 100) / 100.0
      end

      # Allocation bucket for the experiment entries of a multi-experiment flag.
      # Uses the same mixed hash as mixed_normalized_hash, so every bucket bit
      # depends on every input byte.
      #
      # @param key [String] Key to hash (typically distinct_id)
      # @param salt [String] Salt value (flag key followed by the flag's hash salt)
      # @return [Integer] Bucket between 0 and 99
      def self.allocation_bucket(key, salt)
        fmix64(fnv1a_64(key.to_s + salt.to_s)) % 100
      end

      # Normalized hash for variant assignment within an experiment entry of a
      # multi-experiment flag. Passes FNV-1a through the MurmurHash3 64-bit
      # finalizer so every output bit depends on every input byte.
      #
      # @param key [String] Key to hash (typically distinct_id)
      # @param salt [String] Salt value (flag-specific)
      # @return [Float] Value between 0.0 and 1.0 (non-inclusive upper bound)
      def self.mixed_normalized_hash(key, salt)
        (fmix64(fnv1a_64(key.to_s + salt.to_s)) % 100) / 100.0
      end

      # MurmurHash3 64-bit finalizer
      #
      # @param value [Integer] 64-bit value
      # @return [Integer] 64-bit mixed value
      def self.fmix64(value)
        value ^= value >> 33
        value = (value * 0xff51afd7ed558ccd) & 0xffffffffffffffff
        value ^= value >> 33
        value = (value * 0xc4ceb9fe1a85ec53) & 0xffffffffffffffff
        value ^ (value >> 33)
      end

      # Prepare common query parameters for flags API
      #
      # @param token [String] Mixpanel project token
      # @param $lib_version [String] SDK version
      # @return [Hash] Query parameters
      def self.prepare_common_query_params(token, lib_version)
        {
          'mp_lib' => 'ruby',
          '$lib_version' => lib_version,
          'token' => token
        }
      end

      # Generate W3C traceparent header for distributed tracing
      # Format: 00-{trace-id}-{parent-id}-{trace-flags}
      #
      # @return [String] traceparent header value
      def self.generate_traceparent
        version = '00'
        trace_id = SecureRandom.hex(16)
        parent_id = SecureRandom.hex(8)
        trace_flags = '01'  # sampled

        "#{version}-#{trace_id}-#{parent_id}-#{trace_flags}"
      end
    end
  end
end
