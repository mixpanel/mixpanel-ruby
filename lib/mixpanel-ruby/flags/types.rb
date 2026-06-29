module Mixpanel
  module Flags
    # Where a SelectedVariant came from. Set by the providers on every returned
    # variant — coarse-grained (local / remote / fallback). For the specific
    # reason behind a fallback, see {FallbackReason}.
    module VariantSource
      LOCAL    = 'local'.freeze
      REMOTE   = 'remote'.freeze
      FALLBACK = 'fallback'.freeze
    end

    # Why the SDK returned the developer fallback. Only meaningful when
    # SelectedVariant#variant_source == VariantSource::FALLBACK.
    #
    # `kind` is the discriminator (matches the PHP constant set). `message`
    # is set on the reasons that carry useful detail (BACKEND_ERROR with the
    # backend's response, MISSING_CONTEXT_KEY with the missing attribute);
    # nil otherwise. The OpenFeature wrapper dispatches on kind and forwards
    # message into ResolutionDetails#error_message.
    class FallbackReason
      KINDS = %i[flag_not_found missing_context_key no_rollout_match backend_error not_ready].freeze

      attr_reader :kind, :message

      def initialize(kind, message: nil)
        raise ArgumentError, "Unknown FallbackReason kind: #{kind.inspect}" unless KINDS.include?(kind)

        @kind = kind
        @message = message
        freeze
      end

      def ==(other)
        other.is_a?(FallbackReason) && other.kind == @kind && other.message == @message
      end
      alias_method :eql?, :==

      def hash
        [self.class, @kind, @message].hash
      end

      def to_h
        { kind: @kind, message: @message }.compact
      end

      # Factory methods. Reasons without meaningful detail return a frozen
      # singleton; reasons with detail allocate per call.
      def self.flag_not_found;      FLAG_NOT_FOUND;   end
      def self.no_rollout_match;    NO_ROLLOUT_MATCH; end
      def self.not_ready;           NOT_READY;        end
      def self.missing_context_key(key = nil); new(:missing_context_key, message: key); end
      def self.backend_error(message); new(:backend_error, message: message); end

      FLAG_NOT_FOUND   = new(:flag_not_found)
      NO_ROLLOUT_MATCH = new(:no_rollout_match)
      NOT_READY        = new(:not_ready)
    end

    # Selected variant returned from flag evaluation
    class SelectedVariant
      attr_accessor :variant_key, :variant_value, :experiment_id,
                    :is_experiment_active, :is_qa_tester,
                    :variant_source, :fallback_reason

      def initialize(variant_key: nil, variant_value: nil, experiment_id: nil,
                     is_experiment_active: nil, is_qa_tester: nil,
                     variant_source: nil, fallback_reason: nil)
        @variant_key = variant_key
        @variant_value = variant_value
        @experiment_id = experiment_id
        @is_experiment_active = is_experiment_active
        @is_qa_tester = is_qa_tester
        @variant_source = variant_source
        @fallback_reason = fallback_reason
      end

      # Return a copy of this variant tagged with the given source. Clears
      # fallback_reason — use {#as_fallback} when returning a fallback.
      def with_source(source)
        copy_with(variant_source: source, fallback_reason: nil)
      end

      # Return a copy tagged as a fallback with the given reason.
      def as_fallback(reason)
        copy_with(variant_source: VariantSource::FALLBACK, fallback_reason: reason)
      end

      # Convert to hash representation
      def to_h
        {
          variant_key: @variant_key,
          variant_value: @variant_value,
          experiment_id: @experiment_id,
          is_experiment_active: @is_experiment_active,
          is_qa_tester: @is_qa_tester,
          variant_source: @variant_source,
          fallback_reason: @fallback_reason
        }.compact
      end

      private

      def copy_with(variant_source: @variant_source, fallback_reason: @fallback_reason)
        SelectedVariant.new(
          variant_key: @variant_key,
          variant_value: @variant_value,
          experiment_id: @experiment_id,
          is_experiment_active: @is_experiment_active,
          is_qa_tester: @is_qa_tester,
          variant_source: variant_source,
          fallback_reason: fallback_reason
        )
      end
    end
  end
end
