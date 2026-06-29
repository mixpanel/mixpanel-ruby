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
    # SelectedVariant#variant_source == VariantSource::FALLBACK. Matches the
    # constant set used by mixpanel-php so the OpenFeature wrapper can map to
    # the spec-correct error code instead of collapsing every fallback to
    # FLAG_NOT_FOUND.
    module FallbackReason
      FLAG_NOT_FOUND      = 'FLAG_NOT_FOUND'.freeze
      MISSING_CONTEXT_KEY = 'MISSING_CONTEXT_KEY'.freeze
      NO_ROLLOUT_MATCH    = 'NO_ROLLOUT_MATCH'.freeze
      BACKEND_ERROR       = 'BACKEND_ERROR'.freeze
      NOT_READY           = 'NOT_READY'.freeze
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
