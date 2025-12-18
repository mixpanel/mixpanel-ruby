require 'json'
require 'mixpanel-ruby/flags/remote_flags_provider'
require 'mixpanel-ruby/flags/types'
require 'webmock/rspec'

describe Mixpanel::Flags::RemoteFlagsProvider do
  let(:test_token) { 'test-token' }
  let(:test_context) { { 'distinct_id' => 'user123' } }
  let(:endpoint_url_regex) { %r{https://api\.mixpanel\.com/flags} }
  let(:mock_tracker) { double('tracker').as_null_object }
  let(:mock_error_handler) { double('error_handler', handle: nil) }
  let(:config) { {} }

  let(:provider) do
    Mixpanel::Flags::RemoteFlagsProvider.new(
      test_token,
      config,
      mock_tracker,
      mock_error_handler
    )
  end

  before(:each) do
    WebMock.reset!
    WebMock.disable_net_connect!(allow_localhost: false)
  end

  def create_success_response(flags_with_selected_variant)
    {
      code: 200,
      flags: flags_with_selected_variant
    }
  end

  def stub_flags_request(response_body)
    stub_request(:get, endpoint_url_regex)
      .to_return(
        status: 200,
        body: response_body.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )

  end

  def stub_flags_request_failure(status_code)
    stub_request(:get, endpoint_url_regex)
      .with(basic_auth: [test_token, ''])
      .to_return(status: status_code)
  end

  def stub_flags_request_error(error)
    stub_request(:get, endpoint_url_regex)
      .with(basic_auth: [test_token, ''])
      .to_raise(error)
  end

  describe '#get_variant_value' do
    it 'returns fallback value if call fails' do
      stub_flags_request_error(Errno::ECONNREFUSED)

      result = provider.get_variant_value('test_flag', 'control', test_context)
      expect(result).to eq('control')
    end

    it 'returns fallback value if bad response format' do
      stub_request(:get, %r{api\.mixpanel\.com/flags})
        .to_return(
          status: 200,
          body: 'invalid json',
          headers: { 'Content-Type' => 'text/plain' }
        )

      result = provider.get_variant_value('test_flag', 'control', test_context)
      expect(result).to eq('control')
    end

    it 'returns fallback value if success but no flag found' do
      stub_flags_request(create_success_response({}))

      result = provider.get_variant_value('test_flag', 'control', test_context)
      expect(result).to eq('control')
    end

    it 'returns expected variant from API' do
      response = create_success_response({
        'test_flag' => {
          'variant_key' => 'treatment',
          'variant_value' => 'treatment'
        }
      })
      stub_flags_request(response)

      result = provider.get_variant_value('test_flag', 'control', test_context)
      expect(result).to eq('treatment')
    end

    it 'tracks exposure event if variant selected' do
      response = create_success_response({
        'test_flag' => {
          'variant_key' => 'treatment',
          'variant_value' => 'treatment'
        }
      })
      stub_flags_request(response)

      expect(mock_tracker).to receive(:call).once

      provider.get_variant_value('test_flag', 'control', test_context)
    end

    it 'does not track exposure event if fallback' do
      stub_flags_request_error(Errno::ECONNREFUSED)

      expect(mock_tracker).not_to receive(:call)

      provider.get_variant_value('test_flag', 'control', test_context)
    end

    it 'does not track exposure event when report_exposure is false' do
      response = create_success_response({
        'test_flag' => {
          'variant_key' => 'treatment',
          'variant_value' => 'treatment'
        }
      })
      stub_flags_request(response)

      expect(mock_tracker).not_to receive(:call)

      provider.get_variant_value('test_flag', 'control', test_context, report_exposure: false)
    end

    it 'handles different variant value types' do
      # Test string
      response = create_success_response({
        'string_flag' => {
          'variant_key' => 'treatment',
          'variant_value' => 'text-value'
        }
      })
      stub_flags_request(response)
      result = provider.get_variant_value('string_flag', 'default', test_context, report_exposure: false)
      expect(result).to eq('text-value')

      # Test number
      WebMock.reset!
      response = create_success_response({
        'number_flag' => {
          'variant_key' => 'treatment',
          'variant_value' => 42
        }
      })
      stub_flags_request(response)
      result = provider.get_variant_value('number_flag', 0, test_context, report_exposure: false)
      expect(result).to eq(42)

      # Test object
      WebMock.reset!
      response = create_success_response({
        'object_flag' => {
          'variant_key' => 'treatment',
          'variant_value' => { 'key' => 'value' }
        }
      })
      stub_flags_request(response)
      result = provider.get_variant_value('object_flag', {}, test_context, report_exposure: false)
      expect(result).to eq({ 'key' => 'value' })
    end
  end

  describe '#get_variant' do
    it 'returns variant when served' do
      response = create_success_response({
        'new-feature' => {
          'variant_key' => 'on',
          'variant_value' => true
        }
      })
      stub_flags_request(response)

      fallback_variant = Mixpanel::Flags::SelectedVariant.new(variant_value: false)
      result = provider.get_variant('new-feature', fallback_variant, test_context, report_exposure: false)

      expect(result.variant_key).to eq('on')
      expect(result.variant_value).to eq(true)
    end

    it 'selects fallback variant when no flags are served' do
      stub_flags_request(create_success_response({}))

      fallback_variant = Mixpanel::Flags::SelectedVariant.new(
        variant_key: 'control',
        variant_value: false
      )
      result = provider.get_variant('any-flag', fallback_variant, test_context)

      expect(result.variant_key).to eq('control')
      expect(result.variant_value).to eq(false)
      expect(mock_tracker).not_to have_received(:call)
    end

    it 'selects fallback variant if flag does not exist in served flags' do
      response = create_success_response({
        'different-flag' => {
          'variant_key' => 'on',
          'variant_value' => true
        }
      })
      stub_flags_request(response)

      fallback_variant = Mixpanel::Flags::SelectedVariant.new(
        variant_key: 'control',
        variant_value: false
      )
      result = provider.get_variant('missing-flag', fallback_variant, test_context)

      expect(result.variant_key).to eq('control')
      expect(result.variant_value).to eq(false)
      expect(mock_tracker).not_to have_received(:call)
    end

    it 'tracks exposure event when variant is selected' do
      response = create_success_response({
        'test-flag' => {
          'variant_key' => 'treatment',
          'variant_value' => true
        }
      })
      stub_flags_request(response)

      fallback_variant = Mixpanel::Flags::SelectedVariant.new(
        variant_key: 'control',
        variant_value: false
      )

      expect(mock_tracker).to receive(:call) do |distinct_id, event_name, properties|
        expect(distinct_id).to eq('user123')
        expect(event_name).to eq('$experiment_started')
        expect(properties['Experiment name']).to eq('test-flag')
        expect(properties['Variant name']).to eq('treatment')
        expect(properties['$experiment_type']).to eq('feature_flag')
        expect(properties['Flag evaluation mode']).to eq('remote')
      end

      provider.get_variant('test-flag', fallback_variant, test_context)
    end

    it 'does not track exposure event when fallback variant is selected' do
      stub_flags_request(create_success_response({}))

      fallback_variant = Mixpanel::Flags::SelectedVariant.new(
        variant_key: 'control',
        variant_value: false
      )

      expect(mock_tracker).not_to receive(:call)

      provider.get_variant('any-flag', fallback_variant, test_context)
    end
  end

  describe '#is_enabled' do
    it 'returns true when variant value is boolean true' do
      response = create_success_response({
        'test_flag' => {
          'variant_key' => 'on',
          'variant_value' => true
        }
      })
      stub_flags_request(response)

      result = provider.is_enabled('test_flag', test_context)
      expect(result).to eq(true)
    end

    it 'returns false when variant value is boolean false' do
      response = create_success_response({
        'test_flag' => {
          'variant_key' => 'off',
          'variant_value' => false
        }
      })
      stub_flags_request(response)

      result = provider.is_enabled('test_flag', test_context)
      expect(result).to eq(false)
    end

    it 'returns false for truthy non-boolean values' do
      # Test string "true"
      response = create_success_response({
        'string_flag' => {
          'variant_key' => 'treatment',
          'variant_value' => 'true'
        }
      })
      stub_flags_request(response)

      expect(mock_tracker).to receive(:call).once
      result = provider.is_enabled('string_flag', test_context)
      expect(result).to eq(false)

      # Test number 1
      WebMock.reset!
      response = create_success_response({
        'number_flag' => {
          'variant_key' => 'treatment',
          'variant_value' => 1
        }
      })
      stub_flags_request(response)

      expect(mock_tracker).to receive(:call).once
      result = provider.is_enabled('number_flag', test_context)
      expect(result).to eq(false)
    end

    it 'returns false when flag does not exist' do
      response = create_success_response({
        'different-flag' => {
          'variant_key' => 'on',
          'variant_value' => true
        }
      })
      stub_flags_request(response)

      result = provider.is_enabled('missing-flag', test_context)
      expect(result).to eq(false)
    end

    it 'tracks exposure event' do
      response = create_success_response({
        'test_flag' => {
          'variant_key' => 'on',
          'variant_value' => true
        }
      })
      stub_flags_request(response)

      expect(mock_tracker).to receive(:call) do |distinct_id, event_name, properties|
        expect(event_name).to eq('$experiment_started')
        expect(properties['Experiment name']).to eq('test_flag')
        expect(properties['Variant name']).to eq('on')
      end

      provider.is_enabled('test_flag', test_context)
    end

    it 'returns false on network error' do
      stub_flags_request_error(Errno::ECONNREFUSED)

      result = provider.is_enabled('test_flag', test_context)
      expect(result).to eq(false)
    end
  end

  describe '#get_all_variants' do
    it 'returns all variants from API' do
      response = create_success_response({
        'flag-1' => {
          'variant_key' => 'treatment',
          'variant_value' => true
        },
        'flag-2' => {
          'variant_key' => 'control',
          'variant_value' => false
        },
        'flag-3' => {
          'variant_key' => 'blue',
          'variant_value' => 'blue-theme'
        }
      })
      stub_flags_request(response)

      result = provider.get_all_variants(test_context)

      expect(result.keys).to contain_exactly('flag-1', 'flag-2', 'flag-3')
      expect(result['flag-1'].variant_key).to eq('treatment')
      expect(result['flag-1'].variant_value).to eq(true)
      expect(result['flag-2'].variant_key).to eq('control')
      expect(result['flag-2'].variant_value).to eq(false)
      expect(result['flag-3'].variant_key).to eq('blue')
      expect(result['flag-3'].variant_value).to eq('blue-theme')
    end

    it 'returns empty hash when no flags served' do
      stub_flags_request(create_success_response({}))

      result = provider.get_all_variants(test_context)

      expect(result).to eq({})
    end

    it 'does not track any exposure events' do
      response = create_success_response({
        'flag-1' => {
          'variant_key' => 'treatment',
          'variant_value' => true
        },
        'flag-2' => {
          'variant_key' => 'control',
          'variant_value' => false
        }
      })
      stub_flags_request(response)

      expect(mock_tracker).not_to receive(:call)

      provider.get_all_variants(test_context)
    end

    it 'returns nil on network error' do
      stub_flags_request_error(Errno::ECONNREFUSED)

      result = provider.get_all_variants(test_context)

      expect(result).to be_nil
    end

    it 'handles empty response' do
      stub_flags_request(create_success_response({}))

      result = provider.get_all_variants(test_context)

      expect(result).to eq({})
    end
  end

  describe '#track_exposure_event' do
    it 'successfully tracks' do
      variant = Mixpanel::Flags::SelectedVariant.new(
        variant_key: 'treatment',
        variant_value: 'treatment'
      )

      expect(mock_tracker).to receive(:call).once

      provider.send(:track_exposure_event, 'test_flag', variant, test_context)
    end
  end
end
