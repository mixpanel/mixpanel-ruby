require 'json'
require 'mixpanel-ruby/flags/types'

describe Mixpanel::Flags::SelectedVariant do
  describe '#to_h' do
    it 'returns a plain hash for a matched variant' do
      variant = described_class.new(
        variant_key: 'treatment',
        variant_value: 'v1',
        experiment_id: 'exp-1',
        is_experiment_active: true,
        variant_source: Mixpanel::Flags::VariantSource::LOCAL
      )

      expect(variant.to_h).to eq(
        variant_key: 'treatment',
        variant_value: 'v1',
        experiment_id: 'exp-1',
        is_experiment_active: true,
        variant_source: 'local'
      )
    end

    # SDK-125: previously to_h returned the raw FallbackReason object under
    # :fallback_reason, so downstream serializers (e.g. .to_json,
    # structured logging) got an object representation instead of the
    # {kind:, message:} hash FallbackReason itself defines.
    it 'recurses into FallbackReason so the result is fully hash-y' do
      variant = described_class.new(
        variant_value: 'fallback-value',
        variant_source: Mixpanel::Flags::VariantSource::FALLBACK,
        fallback_reason: Mixpanel::Flags::FallbackReason.backend_error('boom')
      )

      expect(variant.to_h[:fallback_reason]).to eq(kind: :backend_error, message: 'boom')
    end

    it 'round-trips through JSON without leaking a FallbackReason object' do
      variant = described_class.new(
        variant_value: 'fallback-value',
        variant_source: Mixpanel::Flags::VariantSource::FALLBACK,
        fallback_reason: Mixpanel::Flags::FallbackReason.missing_context_key('distinct_id')
      )

      parsed = JSON.parse(variant.to_h.to_json, symbolize_names: true)

      expect(parsed[:fallback_reason]).to eq(kind: 'missing_context_key', message: 'distinct_id')
    end

    it 'compacts fallback_reason when absent' do
      variant = described_class.new(variant_value: 'x', variant_source: 'local')
      expect(variant.to_h).not_to have_key(:fallback_reason)
    end
  end
end
