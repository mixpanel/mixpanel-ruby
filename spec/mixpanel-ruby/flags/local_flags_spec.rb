require 'json'
require 'mixpanel-ruby/flags/local_flags_provider'
require 'mixpanel-ruby/flags/types'
require 'webmock/rspec'

describe Mixpanel::Flags::LocalFlagsProvider do
  let(:test_token) { 'test-token' }
  let(:test_context) { { 'distinct_id' => 'user123' } }
  let(:endpoint_url_regex) { %r{https://api\.mixpanel\.com/flags/definitions} }
  let(:mock_tracker) { double('tracker').as_null_object }
  let(:mock_error_handler) { double('error_handler', handle: nil) }
  let(:config) { { enable_polling: false } }

  let(:provider) do
    Mixpanel::Flags::LocalFlagsProvider.new(
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

  after(:each) do
    provider.stop_polling_for_definitions
  end

  def create_test_flag(options = {})
    flag_key = options[:flag_key] || 'test_flag'
    context = options[:context] || 'distinct_id'
    variants = options[:variants] || [
      { 'key' => 'control', 'value' => 'control', 'is_control' => true, 'split' => 50.0 },
      { 'key' => 'treatment', 'value' => 'treatment', 'is_control' => false, 'split' => 50.0 }
    ]
    variant_override = options[:variant_override]
    rollout_percentage = options[:rollout_percentage] || 100.0
    runtime_evaluation_rule = options[:runtime_evaluation_rule]
    test_users = options[:test_users]
    experiment_id = options[:experiment_id]
    is_experiment_active = options[:is_experiment_active]
    variant_splits = options[:variant_splits]
    hash_salt = options[:hash_salt]

    rollout = [
      {
        'rollout_percentage' => rollout_percentage,
        'runtime_evaluation_rule' => runtime_evaluation_rule,
        'variant_override' => variant_override,
        'variant_splits' => variant_splits
      }.compact
    ]

    test_config = test_users ? { 'users' => test_users } : nil

    {
      'id' => 'test-id',
      'name' => 'Test Flag',
      'key' => flag_key,
      'status' => 'active',
      'project_id' => 123,
      'context' => context,
      'experiment_id' => experiment_id,
      'is_experiment_active' => is_experiment_active,
      'hash_salt' => hash_salt,
      'ruleset' => {
        'variants' => variants,
        'rollout' => rollout,
        'test' => test_config
      }.compact
    }.compact
  end

  def stub_flag_definitions(flags)
    response = {
      code: 200,
      flags: flags
    }

    stub_request(:get, endpoint_url_regex)
      .to_return(
        status: 200,
        body: response.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
  end

  def stub_flag_definitions_failure(status_code)
    stub_request(:get, endpoint_url_regex)
      .to_return(status: status_code)
  end

  def user_context_with_properties(properties)
    {
      'distinct_id' => 'user123',
      'custom_properties' => properties
    }
  end

  describe '#get_variant_value' do
    it 'returns fallback when no flag definitions' do
      stub_flag_definitions([])
      provider.start_polling_for_definitions

      result = provider.get_variant_value('nonexistent_flag', 'control', test_context)
      expect(result).to eq('control')
      expect(mock_tracker).not_to have_received(:call)
    end

    it 'returns fallback if flag definition call fails' do
      stub_flag_definitions_failure(500)
      provider.start_polling_for_definitions

      result = provider.get_variant_value('nonexistent_flag', 'control', test_context)
      expect(result).to eq('control')
    end

    it 'returns fallback when flag does not exist' do
      other_flag = create_test_flag(flag_key: 'other_flag')
      stub_flag_definitions([other_flag])
      provider.start_polling_for_definitions

      result = provider.get_variant_value('nonexistent_flag', 'control', test_context)
      expect(result).to eq('control')
    end

    it 'returns fallback when no context' do
      flag = create_test_flag(context: 'distinct_id')
      stub_flag_definitions([flag])
      provider.start_polling_for_definitions

      result = provider.get_variant_value('test_flag', 'fallback', {})
      expect(result).to eq('fallback')
    end

    it 'returns fallback when wrong context key' do
      flag = create_test_flag(context: 'user_id')
      stub_flag_definitions([flag])
      provider.start_polling_for_definitions

      result = provider.get_variant_value('test_flag', 'fallback', { 'distinct_id' => 'user123' })
      expect(result).to eq('fallback')
    end

    it 'returns test user variant when configured' do
      variants = [
        { 'key' => 'control', 'value' => 'false', 'is_control' => true, 'split' => 50.0 },
        { 'key' => 'treatment', 'value' => 'true', 'is_control' => false, 'split' => 50.0 }
      ]
      flag = create_test_flag(
        variants: variants,
        test_users: { 'test_user' => 'treatment' }
      )

      stub_flag_definitions([flag])
      provider.start_polling_for_definitions

      result = provider.get_variant_value('test_flag', 'control', { 'distinct_id' => 'test_user' })
      expect(result).to eq('true')
    end

    it 'returns correct variant when test user variant not configured' do
      variants = [
        { 'key' => 'control', 'value' => 'false', 'is_control' => true, 'split' => 50.0 },
        { 'key' => 'treatment', 'value' => 'true', 'is_control' => false, 'split' => 50.0 }
      ]
      flag = create_test_flag(
        variants: variants,
        test_users: { 'test_user' => 'nonexistent_variant' }
      )

      stub_flag_definitions([flag])
      provider.start_polling_for_definitions

      result = provider.get_variant_value('test_flag', 'fallback', { 'distinct_id' => 'test_user' })
      expect(['false', 'true']).to include(result)
    end

    it 'returns fallback when rollout percentage zero' do
      flag = create_test_flag(rollout_percentage: 0.0)
      stub_flag_definitions([flag])
      provider.start_polling_for_definitions

      result = provider.get_variant_value('test_flag', 'fallback', test_context)
      expect(result).to eq('fallback')
    end

    it 'returns variant when rollout percentage hundred' do
      flag = create_test_flag(rollout_percentage: 100.0)
      stub_flag_definitions([flag])
      provider.start_polling_for_definitions

      result = provider.get_variant_value('test_flag', 'fallback', test_context)
      expect(result).not_to eq('fallback')
      expect(['control', 'treatment']).to include(result)
    end

    it 'respects runtime evaluation rule with equality operator when satisfied' do
      runtime_eval = {
        '==' => [{'var' => 'plan'}, 'premium']
      }
      flag = create_test_flag(runtime_evaluation_rule: runtime_eval)

      stub_flag_definitions([flag])
      provider.start_polling_for_definitions

      context = user_context_with_properties({'plan' => 'premium'})
      result = provider.get_variant_value('test_flag', 'fallback', context)

      expect(result).not_to eq('fallback')
      expect(['control', 'treatment']).to include(result)
    end

    it 'respects runtime evaluation rule with equality operator when not satisfied' do
      runtime_eval = {
        '==' => [{'var' => 'plan'}, 'premium']
      }
      flag = create_test_flag(runtime_evaluation_rule: runtime_eval)

      stub_flag_definitions([flag])
      provider.start_polling_for_definitions

      context = user_context_with_properties({'plan' => 'basic'})
      result = provider.get_variant_value('test_flag', 'fallback', context)

      expect(result).to eq('fallback')
    end

    it 'returns fallback when runtime rule is invalid' do
      runtime_eval = {
        '=oops=' => [{'var' => 'plan'}, 'premium']
      }
      flag = create_test_flag(runtime_evaluation_rule: runtime_eval)

      stub_flag_definitions([flag])
      provider.start_polling_for_definitions

      context = user_context_with_properties({'plan' => 'premium'})
      result = provider.get_variant_value('test_flag', 'fallback', context)

      expect(result).to eq('fallback')
    end

    it 'returns fallback when runtime evaluation rule used but no custom properties provided' do
      runtime_eval = {
        '==' => [{'var' => 'plan'}, 'premium']
      }
      flag = create_test_flag(runtime_evaluation_rule: runtime_eval)

      stub_flag_definitions([flag])
      provider.start_polling_for_definitions

      context = {'distinct_id' => 'user123', 'custom_properties' => {}}
      result = provider.get_variant_value('test_flag', 'fallback', context)

      expect(result).to eq('fallback')
    end

    it 'respects runtime evaluation rule case-insensitive param value when satisfied' do
      runtime_eval = {
        '==' => [{'var' => 'plan'}, 'premium']
      }
      flag = create_test_flag(runtime_evaluation_rule: runtime_eval)

      stub_flag_definitions([flag])
      provider.start_polling_for_definitions

      context = user_context_with_properties({'plan' => 'PremIum'})
      result = provider.get_variant_value('test_flag', 'fallback', context)

      expect(result).not_to eq('fallback')
      expect(['control', 'treatment']).to include(result)
    end

    it 'respects runtime evaluation rule case-insensitive var names when satisfied' do
      runtime_eval = {
        '==' => [{'var' => 'Plan'}, 'premium']
      }
      flag = create_test_flag(runtime_evaluation_rule: runtime_eval)

      stub_flag_definitions([flag])
      provider.start_polling_for_definitions

      context = user_context_with_properties({'plan' => 'premium'})
      result = provider.get_variant_value('test_flag', 'fallback', context)

      expect(result).not_to eq('fallback')
      expect(['control', 'treatment']).to include(result)
    end

    it 'respects runtime evaluation rule case-insensitive rule value when satisfied' do
      runtime_eval = {
        '==' => [{'var' => 'plan'}, 'pREMIUm']
      }
      flag = create_test_flag(runtime_evaluation_rule: runtime_eval)

      stub_flag_definitions([flag])
      provider.start_polling_for_definitions

      context = user_context_with_properties({'plan' => 'premium'})
      result = provider.get_variant_value('test_flag', 'fallback', context)

      expect(result).not_to eq('fallback')
      expect(['control', 'treatment']).to include(result)
    end

    it 'respects runtime evaluation rule with contains operator when satisfied' do
      runtime_eval = {
        'in' => ['Springfield', {'var' => 'url'}]
      }
      flag = create_test_flag(runtime_evaluation_rule: runtime_eval)

      stub_flag_definitions([flag])
      provider.start_polling_for_definitions

      context = user_context_with_properties({'url' => 'https://helloworld.com/Springfield/all-about-it'})
      result = provider.get_variant_value('test_flag', 'fallback', context)

      expect(result).not_to eq('fallback')
      expect(['control', 'treatment']).to include(result)
    end

    it 'respects runtime evaluation rule with contains operator when not satisfied' do
      runtime_eval = {
        'in' => ['Springfield', {'var' => 'url'}]
      }
      flag = create_test_flag(runtime_evaluation_rule: runtime_eval)

      stub_flag_definitions([flag])
      provider.start_polling_for_definitions

      context = user_context_with_properties({'url' => 'https://helloworld.com/Boston/all-about-it'})
      result = provider.get_variant_value('test_flag', 'fallback', context)

      expect(result).to eq('fallback')
    end

    it 'respects runtime evaluation rule with multi-value in operator when satisfied' do
      runtime_eval = {
        'in' => [
          {'var' => 'name'},
          ['a', 'b', 'c', 'all-from-the-ui']
        ]
      }
      flag = create_test_flag(runtime_evaluation_rule: runtime_eval)

      stub_flag_definitions([flag])
      provider.start_polling_for_definitions

      context = user_context_with_properties({'name' => 'b'})
      result = provider.get_variant_value('test_flag', 'fallback', context)

      expect(result).not_to eq('fallback')
      expect(['control', 'treatment']).to include(result)
    end

    it 'respects runtime evaluation rule with multi-value in operator when not satisfied' do
      runtime_eval = {
        'in' => [
          {'var' => 'name'},
          ['a', 'b', 'c', 'all-from-the-ui']
        ]
      }
      flag = create_test_flag(runtime_evaluation_rule: runtime_eval)

      stub_flag_definitions([flag])
      provider.start_polling_for_definitions

      context = user_context_with_properties({'name' => 'd'})
      result = provider.get_variant_value('test_flag', 'fallback', context)

      expect(result).to eq('fallback')
    end

    it 'respects runtime evaluation rule with AND operator when satisfied' do
      runtime_eval = {
        'and' => [
          {'==' => [{'var' => 'name'}, 'Johannes']},
          {'==' => [{'var' => 'country'}, 'Deutschland']}
        ]
      }
      flag = create_test_flag(runtime_evaluation_rule: runtime_eval)

      stub_flag_definitions([flag])
      provider.start_polling_for_definitions

      context = user_context_with_properties({
        'name' => 'Johannes',
        'country' => 'Deutschland'
      })
      result = provider.get_variant_value('test_flag', 'fallback', context)

      expect(result).not_to eq('fallback')
      expect(['control', 'treatment']).to include(result)
    end

    it 'respects runtime evaluation rule with AND operator when not satisfied' do
      runtime_eval = {
        'and' => [
          {'==' => [{'var' => 'name'}, 'Johannes']},
          {'==' => [{'var' => 'country'}, 'Deutschland']}
        ]
      }
      flag = create_test_flag(runtime_evaluation_rule: runtime_eval)

      stub_flag_definitions([flag])
      provider.start_polling_for_definitions

      context = user_context_with_properties({
        'name' => 'Johannes',
        'country' => 'France'
      })
      result = provider.get_variant_value('test_flag', 'fallback', context)

      expect(result).to eq('fallback')
    end

    it 'respects runtime evaluation rule with comparison operator when satisfied' do
      runtime_eval = {
        '>' => [
          {'var' => 'queries_ran'},
          25
        ]
      }
      flag = create_test_flag(runtime_evaluation_rule: runtime_eval)

      stub_flag_definitions([flag])
      provider.start_polling_for_definitions

      context = user_context_with_properties({'queries_ran' => 30})
      result = provider.get_variant_value('test_flag', 'fallback', context)

      expect(result).not_to eq('fallback')
      expect(['control', 'treatment']).to include(result)
    end

    it 'respects runtime evaluation rule with comparison operator when not satisfied' do
      runtime_eval = {
        '>' => [
          {'var' => 'queries_ran'},
          25
        ]
      }
      flag = create_test_flag(runtime_evaluation_rule: runtime_eval)

      stub_flag_definitions([flag])
      provider.start_polling_for_definitions

      context = user_context_with_properties({'queries_ran' => 20})
      result = provider.get_variant_value('test_flag', 'fallback', context)

      expect(result).to eq('fallback')
    end

    it 'picks correct variant with hundred percent split' do
      variants = [
        { 'key' => 'A', 'value' => 'variant_a', 'is_control' => false, 'split' => 100.0 },
        { 'key' => 'B', 'value' => 'variant_b', 'is_control' => false, 'split' => 0.0 },
        { 'key' => 'C', 'value' => 'variant_c', 'is_control' => false, 'split' => 0.0 }
      ]
      flag = create_test_flag(
        variants: variants,
        rollout_percentage: 100.0
      )

      stub_flag_definitions([flag])
      provider.start_polling_for_definitions

      result = provider.get_variant_value('test_flag', 'fallback', test_context)
      expect(result).to eq('variant_a')
    end

    it 'picks correct variant with half migrated group splits' do
      variants = [
        { 'key' => 'A', 'value' => 'variant_a', 'is_control' => false, 'split' => 100.0 },
        { 'key' => 'B', 'value' => 'variant_b', 'is_control' => false, 'split' => 0.0 },
        { 'key' => 'C', 'value' => 'variant_c', 'is_control' => false, 'split' => 0.0 }
      ]
      variant_splits = { 'A' => 0.0, 'B' => 100.0, 'C' => 0.0 }
      flag = create_test_flag(
        variants: variants,
        rollout_percentage: 100.0,
        variant_splits: variant_splits
      )

      stub_flag_definitions([flag])
      provider.start_polling_for_definitions

      result = provider.get_variant_value('test_flag', 'fallback', test_context)
      expect(result).to eq('variant_b')
    end

    it 'picks correct variant with full migrated group splits' do
      variants = [
        { 'key' => 'A', 'value' => 'variant_a', 'is_control' => false },
        { 'key' => 'B', 'value' => 'variant_b', 'is_control' => false },
        { 'key' => 'C', 'value' => 'variant_c', 'is_control' => false }
      ]
      variant_splits = { 'A' => 0.0, 'B' => 0.0, 'C' => 100.0 }
      flag = create_test_flag(
        variants: variants,
        rollout_percentage: 100.0,
        variant_splits: variant_splits
      )

      stub_flag_definitions([flag])
      provider.start_polling_for_definitions

      result = provider.get_variant_value('test_flag', 'fallback', test_context)
      expect(result).to eq('variant_c')
    end

    it 'picks overridden variant' do
      variants = [
        { 'key' => 'A', 'value' => 'variant_a', 'is_control' => false, 'split' => 100.0 },
        { 'key' => 'B', 'value' => 'variant_b', 'is_control' => false, 'split' => 0.0 }
      ]
      flag = create_test_flag(
        variants: variants,
        variant_override: { 'key' => 'B' }
      )

      stub_flag_definitions([flag])
      provider.start_polling_for_definitions

      result = provider.get_variant_value('test_flag', 'control', test_context)
      expect(result).to eq('variant_b')
    end

    it 'tracks exposure when variant selected' do
      flag = create_test_flag
      stub_flag_definitions([flag])
      provider.start_polling_for_definitions

      expect(mock_tracker).to receive(:call).once

      provider.get_variant_value('test_flag', 'fallback', test_context)
    end

    it 'tracks exposure with correct properties' do
      flag = create_test_flag(
        experiment_id: 'exp-123',
        is_experiment_active: true,
        test_users: { 'qa_user' => 'treatment' }
      )

      stub_flag_definitions([flag])
      provider.start_polling_for_definitions

      expect(mock_tracker).to receive(:call) do |distinct_id, event_name, properties|
        expect(distinct_id).to eq('qa_user')
        expect(event_name).to eq('$experiment_started')
        expect(properties['$experiment_id']).to eq('exp-123')
        expect(properties['$is_experiment_active']).to eq(true)
        expect(properties['$is_qa_tester']).to eq(true)
      end

      provider.get_variant_value('test_flag', 'fallback', { 'distinct_id' => 'qa_user' })
    end

    it 'does not track exposure on fallback' do
      stub_flag_definitions([])
      provider.start_polling_for_definitions

      expect(mock_tracker).not_to receive(:call)

      provider.get_variant_value('nonexistent_flag', 'fallback', test_context)
    end

    it 'does not track exposure without distinct_id' do
      flag = create_test_flag(context: 'company')
      stub_flag_definitions([flag])
      provider.start_polling_for_definitions

      expect(mock_tracker).not_to receive(:call)

      provider.get_variant_value('test_flag', 'fallback', { 'company_id' => 'company123' })
    end
  end

  describe '#get_variant' do
    it 'returns fallback variant when no flag definitions' do
      stub_flag_definitions([])
      provider.start_polling_for_definitions

      fallback = Mixpanel::Flags::SelectedVariant.new(variant_value: 'control')
      result = provider.get_variant('nonexistent_flag', fallback, test_context)

      expect(result.variant_value).to eq('control')
      expect(mock_tracker).not_to have_received(:call)
    end

    it 'returns variant with correct properties' do
      # TODO: create two variants, one with 0% and one with 100%, and ensure correct selection, please.
      flag = create_test_flag(rollout_percentage: 100.0)
      stub_flag_definitions([flag])
      provider.start_polling_for_definitions

      fallback = Mixpanel::Flags::SelectedVariant.new(variant_value: 'fallback')
      result = provider.get_variant('test_flag', fallback, test_context, report_exposure: false)

      expect(['control', 'treatment']).to include(result.variant_key)
      expect(['control', 'treatment']).to include(result.variant_value)
    end
  end

  describe '#get_all_variants' do
    it 'returns empty hash when no flag definitions' do
      stub_flag_definitions([])
      provider.start_polling_for_definitions

      result = provider.get_all_variants(test_context)

      expect(result).to eq({})
    end

    it 'returns all variants when two flags have 100% rollout' do
      flag1 = create_test_flag(flag_key: 'flag1', rollout_percentage: 100.0)
      flag2 = create_test_flag(flag_key: 'flag2', rollout_percentage: 100.0)

      stub_flag_definitions([flag1, flag2])
      provider.start_polling_for_definitions

      result = provider.get_all_variants(test_context)

      expect(result.keys).to contain_exactly('flag1', 'flag2')
    end

    it 'returns partial results when one flag has 0% rollout' do
      flag1 = create_test_flag(flag_key: 'flag1', rollout_percentage: 100.0)
      flag2 = create_test_flag(flag_key: 'flag2', rollout_percentage: 0.0)

      stub_flag_definitions([flag1, flag2])
      provider.start_polling_for_definitions

      result = provider.get_all_variants(test_context)

      expect(result.keys).to include('flag1')
      expect(result.keys).not_to include('flag2')
    end

    it 'does not track exposure events' do
      flag1 = create_test_flag(flag_key: 'flag1', rollout_percentage: 100.0)
      flag2 = create_test_flag(flag_key: 'flag2', rollout_percentage: 100.0)

      stub_flag_definitions([flag1, flag2])
      provider.start_polling_for_definitions

      expect(mock_tracker).not_to receive(:call)

      provider.get_all_variants(test_context)
    end
  end

  describe '#is_enabled' do
    it 'returns false for nonexistent flag' do
      stub_flag_definitions([])
      provider.start_polling_for_definitions

      result = provider.is_enabled('nonexistent_flag', test_context)
      expect(result).to eq(false)
    end

    it 'returns true for true variant value' do
      variants = [
        { 'key' => 'treatment', 'value' => true, 'is_control' => false, 'split' => 100.0 }
      ]
      flag = create_test_flag(variants: variants, rollout_percentage: 100.0)

      stub_flag_definitions([flag])
      provider.start_polling_for_definitions

      result = provider.is_enabled('test_flag', test_context)
      expect(result).to eq(true)
    end

    it 'returns false for false variant value' do
      variants = [
        { 'key' => 'control', 'value' => false, 'is_control' => true, 'split' => 100.0 }
      ]
      flag = create_test_flag(variants: variants, rollout_percentage: 100.0)

      stub_flag_definitions([flag])
      provider.start_polling_for_definitions

      result = provider.is_enabled('test_flag', test_context)
      expect(result).to eq(false)
    end

    it 'returns false for truthy non-boolean values' do
      variants = [
        { 'key' => 'treatment', 'value' => 'true', 'is_control' => false, 'split' => 100.0 }
      ]
      flag = create_test_flag(variants: variants, rollout_percentage: 100.0)

      stub_flag_definitions([flag])
      provider.start_polling_for_definitions

      result = provider.is_enabled('test_flag', test_context)
      expect(result).to eq(false)
    end
  end

  describe '#track_exposure_event' do
    it 'successfully tracks' do
      flag = create_test_flag
      stub_flag_definitions([flag])
      provider.start_polling_for_definitions

      variant = Mixpanel::Flags::SelectedVariant.new(
        variant_key: 'treatment',
        variant_value: 'treatment'
      )

      expect(mock_tracker).to receive(:call).once

      provider.send(:track_exposure_event, 'test_flag', variant, test_context)
    end
  end

  describe 'polling' do
    it 'uses most recent polled flag definitions' do
      flag_v1 = create_test_flag(rollout_percentage: 0.0)
      flag_v2 = create_test_flag(rollout_percentage: 100.0)

      call_count = 0
      stub_request(:get, endpoint_url_regex)
        .to_return do |request|
          call_count += 1
          flag = call_count == 1 ? flag_v1 : flag_v2
          {
            status: 200,
            body: { code: 200, flags: [flag] }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          }
        end

      polling_provider = Mixpanel::Flags::LocalFlagsProvider.new(
        test_token,
        { enable_polling: true, polling_interval_in_seconds: 0.1 },
        mock_tracker,
        mock_error_handler
      )

      begin
        polling_provider.start_polling_for_definitions

        sleep 0.3

        result = polling_provider.get_variant_value('test_flag', 'fallback', test_context, report_exposure: false)
        expect(result).not_to eq('fallback')
      ensure
        polling_provider.stop_polling_for_definitions
      end
    end
  end
end
