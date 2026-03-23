# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mixpanel::OpenFeature::Provider do
  let(:mock_flags) do
    instance_double('FlagsProvider').tap do |flags|
      allow(flags).to receive(:are_flags_ready).and_return(true)
    end
  end

  let(:provider) { described_class.new(mock_flags) }

  def setup_flag(flag_key, value, variant_key: 'variant-key')
    allow(mock_flags).to receive(:get_variant) do |key, fallback, _ctx|
      if key == flag_key
        Mixpanel::Flags::SelectedVariant.new(variant_key: variant_key, variant_value: value)
      else
        fallback
      end
    end
  end

  def setup_flag_not_found
    allow(mock_flags).to receive(:get_variant) { |_key, fallback, _ctx| fallback }
  end

  # --- Metadata ---

  describe '#metadata' do
    it 'returns mixpanel-provider as the name' do
      expect(provider.metadata.name).to eq('mixpanel-provider')
    end
  end

  # --- Boolean evaluation ---

  describe '#fetch_boolean_value' do
    it 'resolves true' do
      setup_flag('bool-flag', true)
      result = provider.fetch_boolean_value(flag_key: 'bool-flag', default_value: false)
      expect(result.value).to be true
      expect(result.reason).to eq('STATIC')
      expect(result.error_code).to be_nil
    end

    it 'resolves false' do
      setup_flag('bool-flag', false)
      result = provider.fetch_boolean_value(flag_key: 'bool-flag', default_value: true)
      expect(result.value).to be false
      expect(result.reason).to eq('STATIC')
    end

    it 'returns TYPE_MISMATCH when value is not boolean' do
      setup_flag('string-flag', 'not-a-bool')
      result = provider.fetch_boolean_value(flag_key: 'string-flag', default_value: false)
      expect(result.value).to be false
      expect(result.error_code).to eq('TYPE_MISMATCH')
      expect(result.reason).to eq('ERROR')
    end
  end

  # --- String evaluation ---

  describe '#fetch_string_value' do
    it 'resolves a string' do
      setup_flag('string-flag', 'hello')
      result = provider.fetch_string_value(flag_key: 'string-flag', default_value: 'default')
      expect(result.value).to eq('hello')
      expect(result.reason).to eq('STATIC')
      expect(result.error_code).to be_nil
    end

    it 'returns TYPE_MISMATCH when value is not string' do
      setup_flag('bool-flag', true)
      result = provider.fetch_string_value(flag_key: 'bool-flag', default_value: 'default')
      expect(result.value).to eq('default')
      expect(result.error_code).to eq('TYPE_MISMATCH')
      expect(result.reason).to eq('ERROR')
    end
  end

  # --- Integer evaluation ---

  describe '#fetch_integer_value' do
    it 'resolves an integer' do
      setup_flag('int-flag', 42)
      result = provider.fetch_integer_value(flag_key: 'int-flag', default_value: 0)
      expect(result.value).to eq(42)
      expect(result.reason).to eq('STATIC')
      expect(result.error_code).to be_nil
    end

    it 'coerces float with no fraction to integer' do
      setup_flag('int-flag', 42.0)
      result = provider.fetch_integer_value(flag_key: 'int-flag', default_value: 0)
      expect(result.value).to eq(42)
      expect(result.value).to be_a(Integer)
      expect(result.reason).to eq('STATIC')
    end

    it 'returns TYPE_MISMATCH for float with fraction' do
      setup_flag('float-flag', 3.14)
      result = provider.fetch_integer_value(flag_key: 'float-flag', default_value: 0)
      expect(result.value).to eq(0)
      expect(result.error_code).to eq('TYPE_MISMATCH')
      expect(result.reason).to eq('ERROR')
    end

    it 'returns TYPE_MISMATCH when value is a string' do
      setup_flag('string-flag', 'not-a-number')
      result = provider.fetch_integer_value(flag_key: 'string-flag', default_value: 0)
      expect(result.value).to eq(0)
      expect(result.error_code).to eq('TYPE_MISMATCH')
      expect(result.reason).to eq('ERROR')
    end
  end

  # --- Float evaluation ---

  describe '#fetch_float_value' do
    it 'resolves a float' do
      setup_flag('float-flag', 3.14)
      result = provider.fetch_float_value(flag_key: 'float-flag', default_value: 0.0)
      expect(result.value).to be_within(0.001).of(3.14)
      expect(result.reason).to eq('STATIC')
      expect(result.error_code).to be_nil
    end

    it 'coerces integer to float' do
      setup_flag('float-flag', 42)
      result = provider.fetch_float_value(flag_key: 'float-flag', default_value: 0.0)
      expect(result.value).to eq(42.0)
      expect(result.value).to be_a(Float)
      expect(result.reason).to eq('STATIC')
    end

    it 'returns TYPE_MISMATCH when value is a string' do
      setup_flag('string-flag', 'not-a-number')
      result = provider.fetch_float_value(flag_key: 'string-flag', default_value: 0.0)
      expect(result.value).to eq(0.0)
      expect(result.error_code).to eq('TYPE_MISMATCH')
      expect(result.reason).to eq('ERROR')
    end
  end

  # --- Number evaluation ---

  describe '#fetch_number_value' do
    it 'resolves an integer as number' do
      setup_flag('num-flag', 42)
      result = provider.fetch_number_value(flag_key: 'num-flag', default_value: 0)
      expect(result.value).to eq(42)
      expect(result.reason).to eq('STATIC')
    end

    it 'resolves a float as number' do
      setup_flag('num-flag', 3.14)
      result = provider.fetch_number_value(flag_key: 'num-flag', default_value: 0.0)
      expect(result.value).to be_within(0.001).of(3.14)
      expect(result.reason).to eq('STATIC')
    end

    it 'returns TYPE_MISMATCH when value is not numeric' do
      setup_flag('string-flag', 'hello')
      result = provider.fetch_number_value(flag_key: 'string-flag', default_value: 0)
      expect(result.value).to eq(0)
      expect(result.error_code).to eq('TYPE_MISMATCH')
      expect(result.reason).to eq('ERROR')
    end
  end

  # --- Object evaluation ---

  describe '#fetch_object_value' do
    it 'resolves a hash' do
      setup_flag('obj-flag', { 'key' => 'value' })
      result = provider.fetch_object_value(flag_key: 'obj-flag', default_value: {})
      expect(result.value).to eq({ 'key' => 'value' })
      expect(result.reason).to eq('STATIC')
      expect(result.error_code).to be_nil
    end

    it 'resolves an array' do
      setup_flag('obj-flag', [1, 2, 3])
      result = provider.fetch_object_value(flag_key: 'obj-flag', default_value: [])
      expect(result.value).to eq([1, 2, 3])
      expect(result.reason).to eq('STATIC')
    end

    it 'resolves a string as object' do
      setup_flag('obj-flag', 'hello')
      result = provider.fetch_object_value(flag_key: 'obj-flag', default_value: {})
      expect(result.value).to eq('hello')
      expect(result.reason).to eq('STATIC')
    end

    it 'resolves a boolean as object' do
      setup_flag('obj-flag', true)
      result = provider.fetch_object_value(flag_key: 'obj-flag', default_value: {})
      expect(result.value).to be true
      expect(result.reason).to eq('STATIC')
    end
  end

  # --- FLAG_NOT_FOUND ---

  describe 'flag not found' do
    before { setup_flag_not_found }

    it 'returns FLAG_NOT_FOUND for boolean' do
      result = provider.fetch_boolean_value(flag_key: 'missing', default_value: true)
      expect(result.value).to be true
      expect(result.error_code).to eq('FLAG_NOT_FOUND')
      expect(result.reason).to eq('ERROR')
    end

    it 'returns FLAG_NOT_FOUND for string' do
      result = provider.fetch_string_value(flag_key: 'missing', default_value: 'fallback')
      expect(result.value).to eq('fallback')
      expect(result.error_code).to eq('FLAG_NOT_FOUND')
      expect(result.reason).to eq('ERROR')
    end

    it 'returns FLAG_NOT_FOUND for integer' do
      result = provider.fetch_integer_value(flag_key: 'missing', default_value: 99)
      expect(result.value).to eq(99)
      expect(result.error_code).to eq('FLAG_NOT_FOUND')
      expect(result.reason).to eq('ERROR')
    end

    it 'returns FLAG_NOT_FOUND for float' do
      result = provider.fetch_float_value(flag_key: 'missing', default_value: 1.5)
      expect(result.value).to eq(1.5)
      expect(result.error_code).to eq('FLAG_NOT_FOUND')
      expect(result.reason).to eq('ERROR')
    end

    it 'returns FLAG_NOT_FOUND for object' do
      result = provider.fetch_object_value(flag_key: 'missing', default_value: { 'default' => true })
      expect(result.value).to eq({ 'default' => true })
      expect(result.error_code).to eq('FLAG_NOT_FOUND')
      expect(result.reason).to eq('ERROR')
    end
  end

  # --- PROVIDER_NOT_READY ---

  describe 'provider not ready' do
    let(:mock_flags) do
      instance_double('FlagsProvider').tap do |flags|
        allow(flags).to receive(:are_flags_ready).and_return(false)
      end
    end

    it 'returns PROVIDER_NOT_READY for boolean' do
      result = provider.fetch_boolean_value(flag_key: 'any', default_value: true)
      expect(result.value).to be true
      expect(result.error_code).to eq('PROVIDER_NOT_READY')
      expect(result.reason).to eq('ERROR')
    end

    it 'returns PROVIDER_NOT_READY for string' do
      result = provider.fetch_string_value(flag_key: 'any', default_value: 'default')
      expect(result.value).to eq('default')
      expect(result.error_code).to eq('PROVIDER_NOT_READY')
      expect(result.reason).to eq('ERROR')
    end

    it 'returns PROVIDER_NOT_READY for integer' do
      result = provider.fetch_integer_value(flag_key: 'any', default_value: 5)
      expect(result.value).to eq(5)
      expect(result.error_code).to eq('PROVIDER_NOT_READY')
      expect(result.reason).to eq('ERROR')
    end

    it 'returns PROVIDER_NOT_READY for float' do
      result = provider.fetch_float_value(flag_key: 'any', default_value: 2.5)
      expect(result.value).to eq(2.5)
      expect(result.error_code).to eq('PROVIDER_NOT_READY')
      expect(result.reason).to eq('ERROR')
    end

    it 'returns PROVIDER_NOT_READY for object' do
      result = provider.fetch_object_value(flag_key: 'any', default_value: { 'default' => true })
      expect(result.value).to eq({ 'default' => true })
      expect(result.error_code).to eq('PROVIDER_NOT_READY')
      expect(result.reason).to eq('ERROR')
    end
  end

  # --- Remote provider (no are_flags_ready) is always ready ---

  describe 'remote provider without are_flags_ready' do
    let(:remote_flags) do
      double('RemoteFlagsProvider').tap do |flags|
        allow(flags).to receive(:get_variant) do |_key, _fallback, _ctx|
          Mixpanel::Flags::SelectedVariant.new(variant_key: 'v1', variant_value: true)
        end
      end
    end

    let(:provider) { described_class.new(remote_flags) }

    it 'treats provider as ready' do
      result = provider.fetch_boolean_value(flag_key: 'flag', default_value: false)
      expect(result.value).to be true
      expect(result.reason).to eq('STATIC')
    end
  end

  # --- Variant key passthrough ---

  describe 'variant key' do
    it 'includes variant key in successful resolution' do
      setup_flag('flag', 'value', variant_key: 'my-variant')
      result = provider.fetch_string_value(flag_key: 'flag', default_value: 'default')
      expect(result.variant).to eq('my-variant')
      expect(result.reason).to eq('STATIC')
    end

    it 'does not include variant on error' do
      setup_flag_not_found
      result = provider.fetch_string_value(flag_key: 'missing', default_value: 'default')
      expect(result.variant).to be_nil
    end
  end

  # --- Context forwarding ---

  describe 'evaluation context forwarding' do
    it 'forwards evaluation_context fields to get_variant' do
      eval_context = double('EvaluationContext',
        fields: { 'distinct_id' => 'user-1', 'plan' => 'premium' },
        targeting_key: nil
      )
      allow(mock_flags).to receive(:get_variant) do |_key, fallback, ctx|
        expect(ctx).to eq({ 'distinct_id' => 'user-1', 'plan' => 'premium' })
        Mixpanel::Flags::SelectedVariant.new(variant_key: 'v1', variant_value: true)
      end

      provider.fetch_boolean_value(flag_key: 'flag', default_value: false, evaluation_context: eval_context)
    end

    it 'includes targeting_key in context when present' do
      eval_context = double('EvaluationContext',
        fields: { 'distinct_id' => 'user-1' },
        targeting_key: 'tk-123'
      )
      allow(mock_flags).to receive(:get_variant) do |_key, fallback, ctx|
        expect(ctx).to eq({ 'distinct_id' => 'user-1', 'targetingKey' => 'tk-123' })
        Mixpanel::Flags::SelectedVariant.new(variant_key: 'v1', variant_value: true)
      end

      provider.fetch_boolean_value(flag_key: 'flag', default_value: false, evaluation_context: eval_context)
    end

    it 'passes empty hash when evaluation_context is nil' do
      allow(mock_flags).to receive(:get_variant) do |_key, fallback, ctx|
        expect(ctx).to eq({})
        Mixpanel::Flags::SelectedVariant.new(variant_key: 'v1', variant_value: true)
      end

      provider.fetch_boolean_value(flag_key: 'flag', default_value: false)
    end
  end

  # --- SDK exception handling ---

  describe 'SDK exception handling' do
    it 'returns default value with GENERAL error when get_variant raises' do
      allow(mock_flags).to receive(:get_variant).and_raise(RuntimeError, 'unexpected SDK error')

      result = provider.fetch_boolean_value(flag_key: 'flag', default_value: true)
      expect(result.value).to be true
      expect(result.error_code).to eq('GENERAL')
      expect(result.reason).to eq('ERROR')
    end

    it 'returns default value for string when get_variant raises' do
      allow(mock_flags).to receive(:get_variant).and_raise(StandardError, 'connection failed')

      result = provider.fetch_string_value(flag_key: 'flag', default_value: 'fallback')
      expect(result.value).to eq('fallback')
      expect(result.error_code).to eq('GENERAL')
      expect(result.reason).to eq('ERROR')
    end

    it 'returns default value for integer when get_variant raises' do
      allow(mock_flags).to receive(:get_variant).and_raise(StandardError, 'timeout')

      result = provider.fetch_integer_value(flag_key: 'flag', default_value: 42)
      expect(result.value).to eq(42)
      expect(result.error_code).to eq('GENERAL')
      expect(result.reason).to eq('ERROR')
    end
  end

  # --- Null variant key ---

  describe 'null variant key' do
    it 'resolves successfully with nil variant when variant_key is nil' do
      setup_flag('flag', 'hello', variant_key: nil)
      result = provider.fetch_string_value(flag_key: 'flag', default_value: 'default')
      expect(result.value).to eq('hello')
      expect(result.variant).to be_nil
      expect(result.reason).to eq('STATIC')
      expect(result.error_code).to be_nil
    end

    it 'resolves boolean with nil variant key' do
      setup_flag('flag', true, variant_key: nil)
      result = provider.fetch_boolean_value(flag_key: 'flag', default_value: false)
      expect(result.value).to be true
      expect(result.variant).to be_nil
      expect(result.reason).to eq('STATIC')
    end
  end

  # --- Lifecycle ---

  describe '#shutdown' do
    it 'is a no-op' do
      expect { provider.shutdown }.not_to raise_error
    end
  end
end
