require 'json'
require 'mixpanel-ruby'
require 'mixpanel-ruby/flags/local_flags_provider'
require 'mixpanel-ruby/flags/remote_flags_provider'
require 'mixpanel-ruby/flags/types'
require 'webmock/rspec'

describe 'Hierarchical groups feature flags' do
  let(:test_token) { 'test-token' }
  let(:definitions_url_regex) { %r{https://api\.mixpanel\.com/flags/definitions} }
  let(:remote_url_regex) { %r{https://api\.mixpanel\.com/flags\?} }
  let(:error_handler) { double('error_handler', handle: nil) }
  let(:template) { '$company:{$company_id}|$user:{$user_id}' }
  let(:hg_context) { { '$company_id' => 'acme', '$user_id' => 'user-123' } }
  let(:fallback) { 'fallback' }

  before(:each) do
    WebMock.reset!
    WebMock.disable_net_connect!(allow_localhost: false)
  end

  def flag_definition(key: 'hg_flag', context: 'distinct_id', context_template: nil,
                      context_template_version: nil, rollout_percentage: 1.0, test_users: nil,
                      hash_salt: 'salt')
    {
      'id' => 'test-id',
      'name' => 'Test Flag',
      'key' => key,
      'status' => 'active',
      'project_id' => 123,
      'context' => context,
      'context_template' => context_template,
      'context_template_version' => context_template_version,
      'hash_salt' => hash_salt,
      'ruleset' => {
        'variants' => [
          { 'key' => 'control', 'value' => 'value-a', 'split' => 1.0 },
          { 'key' => 'treatment', 'value' => 'treatment-value', 'split' => 0.0 }
        ],
        'rollout' => [{ 'rollout_percentage' => rollout_percentage }],
        'test' => test_users ? { 'users' => test_users } : nil
      }.compact
    }.compact
  end

  def stub_definitions(flags)
    stub_request(:get, definitions_url_regex)
      .to_return(status: 200, body: { code: 200, flags: flags }.to_json,
                 headers: { 'Content-Type' => 'application/json' })
  end

  def local_provider(flags, tracker, hierarchical_groups: false)
    stub_definitions(flags)
    provider = Mixpanel::Flags::LocalFlagsProvider.new(
      test_token, { enable_polling: false }, tracker, error_handler,
      hierarchical_groups: hierarchical_groups
    )
    provider.start_polling_for_definitions!
    provider
  end

  def recording_tracker
    calls = []
    tracker = proc { |distinct_id, event, properties| calls << [distinct_id, event, properties] }
    [tracker, calls]
  end

  def hashed_keys
    keys = []
    allow(Mixpanel::Flags::Utils).to receive(:normalized_hash).and_wrap_original do |original, key, salt|
      keys << key
      original.call(key, salt)
    end
    keys
  end

  describe 'context template parsing' do
    let(:tracker) { recording_tracker.first }

    it 'drops a flag whose context_template_version is newer than the SDK supports' do
      provider = nil
      expect do
        provider = local_provider(
          [flag_definition(context_template: template, context_template_version: 2)], tracker
        )
      end.to output(/Dropping flag 'hg_flag'.*context_template_version 2.*Evaluate it remotely, or upgrade the SDK/).to_stderr

      result = provider.get_variant('hg_flag', Mixpanel::Flags::SelectedVariant.new(variant_value: fallback),
                                    { 'distinct_id' => 'user-123' })
      expect(result.variant_value).to eq(fallback)
      expect(result.fallback_reason).to eq(Mixpanel::Flags::FallbackReason.flag_not_found)
    end

    it 'keeps a flag with context_template_version 1' do
      provider = local_provider([flag_definition(context_template: template, context_template_version: 1)], tracker)
      expect(provider.get_variant_value('hg_flag', fallback, hg_context)).to eq('value-a')
    end

    ['no-placeholders', '{}', '{  }', '$company:{}|$user:{$user_id}', '$company:{ }|$user:{$user_id}'].each do |bad|
      it "drops a flag whose context_template is #{bad.inspect}" do
        provider = nil
        expect do
          provider = local_provider([flag_definition(context_template: bad)], tracker)
        end.to output(/Dropping flag 'hg_flag'.*has no usable placeholders/).to_stderr

        expect(provider.get_variant_value('hg_flag', fallback, { 'distinct_id' => 'user-123' })).to eq(fallback)
      end
    end

    it 'keeps the other flags when one is dropped' do
      provider = nil
      expect do
        provider = local_provider(
          [flag_definition(key: 'good_flag'), flag_definition(context_template: '{}')], tracker
        )
      end.to output(/Dropping flag 'hg_flag'/).to_stderr

      ctx = { 'distinct_id' => 'user-123' }
      expect(provider.get_variant_value('good_flag', fallback, ctx)).to eq('value-a')
      expect(provider.get_variant_value('hg_flag', fallback, ctx)).to eq(fallback)
    end

    it 'treats an empty context_template as none' do
      provider = nil
      expect do
        provider = local_provider([flag_definition(context_template: '')], tracker)
      end.not_to output.to_stderr

      expect(provider.get_variant_value('hg_flag', fallback, hg_context)).to eq(fallback)
      expect(provider.get_variant_value('hg_flag', fallback, { 'distinct_id' => 'user-123' })).to eq('value-a')
    end
  end

  describe 'resolving the assignment key' do
    let(:tracker) { recording_tracker.first }

    it 'gives a template context exactly the variant its distinct id gets' do
      definition = {
        'id' => 'test-id', 'name' => 'HG Test', 'status' => 'active', 'project_id' => 123,
        'key' => 'hg-test', 'serving_method' => 'client', 'context' => 'distinct_id',
        'context_template' => '$company:{$company_id}|$user:{$user_id}',
        'hash_salt' => '880dc3e584b4452fb769808ca18dc9a6',
        'ruleset' => {
          'variants' => [{ 'key' => 'On', 'value' => true, 'split' => 1 },
                         { 'key' => 'Off', 'value' => false, 'split' => 0 }],
          'rollout' => [{ 'rollout_percentage' => 0.5, 'variant_splits' => { 'Off' => 0, 'On' => 1 } }],
          'test' => { 'users' => {} }
        }
      }
      provider = local_provider([definition], tracker)
      fallback_variant = Mixpanel::Flags::SelectedVariant.new(variant_value: 'fallback')

      outcomes = (1..50).map do |i|
        user_id = "u#{i}"
        by_template = provider.get_variant('hg-test', fallback_variant,
                                           { '$company_id' => 'acme', '$user_id' => user_id })
        by_distinct_id = provider.get_variant('hg-test', fallback_variant,
                                              { 'distinct_id' => "$company:acme|$user:#{user_id}" })
        expect([by_template.variant_key, by_template.variant_value, by_template.variant_source])
          .to eq([by_distinct_id.variant_key, by_distinct_id.variant_value, by_distinct_id.variant_source])
        by_template.variant_value
      end
      # Both outcomes occur, so the comparison above is not vacuous.
      expect(outcomes).to include(true, 'fallback')

      user_only = provider.get_variant('hg-test', fallback_variant, { '$user_id' => 'u1' })
      expect(user_only.variant_value).to eq('fallback')
      expect(user_only.fallback_reason).to eq(Mixpanel::Flags::FallbackReason.missing_context_key('distinct_id'))
    end

    it 'hashes the filled template' do
      provider = local_provider([flag_definition(context_template: template)], tracker)
      keys = hashed_keys

      expect(provider.get_variant_value('hg_flag', fallback, hg_context)).to eq('value-a')
      expect(keys.uniq).to eq(['$company:acme|$user:user-123'])
    end

    it 'stringifies non-string context values' do
      provider = local_provider([flag_definition(context_template: template)], tracker)
      keys = hashed_keys

      provider.get_variant_value('hg_flag', fallback, { '$company_id' => 42, '$user_id' => 7 })
      expect(keys.uniq).to eq(['$company:42|$user:7'])
    end

    it 'needs every placeholder to be present and non-empty' do
      provider = local_provider([flag_definition(context_template: template)], tracker)

      expect(provider.get_variant_value('hg_flag', fallback, { '$company_id' => 'acme' })).to eq(fallback)
      expect(provider.get_variant_value('hg_flag', fallback, { '$company_id' => 'acme', '$user_id' => '' })).to eq(fallback)
      expect(provider.get_variant_value('hg_flag', fallback, { '$company_id' => 'acme', '$user_id' => nil })).to eq(fallback)
    end

    it 'hashes a distinct_id as sent, ignoring the template' do
      provider = local_provider([flag_definition(context_template: template)], tracker)
      keys = hashed_keys

      ctx = { 'distinct_id' => '$company:acme|$user:user-123', '$company_id' => 'other', '$user_id' => 'other' }
      expect(provider.get_variant_value('hg_flag', fallback, ctx)).to eq('value-a')
      expect(keys.uniq).to eq(['$company:acme|$user:user-123'])
    end

    it 'hashes a group flag on the raw group value' do
      provider = local_provider([flag_definition(context: 'department')], tracker)
      keys = hashed_keys

      provider.get_variant_value('hg_flag', fallback, hg_context.merge('department' => 'finance'))
      expect(keys.uniq).to eq(['finance'])
    end

    it 'hashes a device flag on the raw device id' do
      provider = local_provider([flag_definition(context: 'device_id')], tracker)
      keys = hashed_keys

      provider.get_variant_value('hg_flag', fallback, hg_context.merge('device_id' => 'device-abc'))
      expect(keys.uniq).to eq(['device-abc'])
    end

    it 'cannot evaluate a hierarchical context locally without a template' do
      provider = local_provider([flag_definition], tracker, hierarchical_groups: true)
      keys = hashed_keys

      expect(provider.get_variant_value('hg_flag', fallback, hg_context)).to eq(fallback)
      expect(keys).to be_empty
    end

    it 'applies the template whether or not hierarchical_groups is set' do
      provider = local_provider([flag_definition(context_template: template)], tracker, hierarchical_groups: false)
      expect(provider.get_variant_value('hg_flag', fallback, hg_context)).to eq('value-a')
    end
  end

  describe 'test user overrides' do
    let(:tracker) { recording_tracker.first }

    it 'matches a test user by the distinct id the template builds' do
      provider = local_provider(
        [flag_definition(context_template: template, test_users: { '$company:acme|$user:user-123' => 'treatment' })],
        tracker
      )
      expect(provider.get_variant_value('hg_flag', fallback, hg_context)).to eq('treatment-value')
    end

    it 'matches a test user by the distinct id as sent' do
      provider = local_provider(
        [flag_definition(context_template: template, test_users: { '$company:acme|$user:user-123' => 'treatment' })],
        tracker, hierarchical_groups: true
      )
      expect(provider.get_variant_value('hg_flag', fallback, { 'distinct_id' => '$company:acme|$user:user-123' }))
        .to eq('treatment-value')
    end

    it 'does not use the template value when the flag assigns on another property' do
      provider = local_provider(
        [flag_definition(context: 'account', context_template: template,
                         test_users: { '$company:acme|$user:user-123' => 'treatment' })],
        tracker
      )
      expect(provider.get_variant_value('hg_flag', fallback, hg_context)).to eq('value-a')
    end
  end

  describe 'local exposure' do
    it 'carries $user_id and $company_id and no distinct_id on a hierarchical groups project' do
      tracker, calls = recording_tracker
      provider = local_provider([flag_definition(context_template: template)], tracker, hierarchical_groups: true)

      expect(provider.get_variant_value('hg_flag', fallback, hg_context)).to eq('value-a')

      expect(calls.size).to eq(1)
      identity, event, properties = calls.first
      expect(identity).to eq(Mixpanel::Identity.new(user_id: 'user-123', company_id: 'acme'))
      expect(event).to eq('$experiment_started')
      expect(properties['$user_id']).to eq('user-123')
      expect(properties['$company_id']).to eq('acme')
      expect(properties).not_to have_key('distinct_id')
      expect(properties['Experiment name']).to eq('hg_flag')
    end

    it 'adds distinct_id when the context has one' do
      tracker, calls = recording_tracker
      provider = local_provider([flag_definition], tracker, hierarchical_groups: true)
      ctx = hg_context.merge('distinct_id' => '$company:acme|$user:user-123')

      provider.get_variant_value('hg_flag', fallback, ctx)

      identity, _, properties = calls.first
      expect(identity).to eq(Mixpanel::Identity.new(distinct_id: '$company:acme|$user:user-123',
                                                    user_id: 'user-123', company_id: 'acme'))
      expect(properties['distinct_id']).to eq('$company:acme|$user:user-123')
      expect(properties['$user_id']).to eq('user-123')
      expect(properties['$company_id']).to eq('acme')
    end

    it 'attributes a hierarchical exposure by $company_id alone' do
      tracker, calls = recording_tracker
      provider = local_provider([flag_definition(context: 'department')], tracker, hierarchical_groups: true)

      provider.get_variant_value('hg_flag', fallback, { '$company_id' => 'acme', 'department' => 'finance' })

      identity, _, properties = calls.first
      expect(identity).to eq(Mixpanel::Identity.new(company_id: 'acme'))
      expect(properties).not_to have_key('distinct_id')
      expect(properties).not_to have_key('$user_id')
    end

    it 'drops a hierarchical exposure without $company_id or distinct_id, naming $company_id' do
      tracker, calls = recording_tracker
      provider = local_provider([flag_definition(context: 'device_id')], tracker, hierarchical_groups: true)

      expect(error_handler).to receive(:handle) do |error|
        expect(error.message).to eq("Cannot track exposure event for flag 'hg_flag' without a $company_id in the context")
      end
      provider.get_variant_value('hg_flag', fallback, { '$user_id' => 'user-123', 'device_id' => 'device-abc', '$company_id' => '' })
      expect(calls).to be_empty
    end

    it 'attributes a hierarchical exposure without $company_id by its distinct_id' do
      tracker, calls = recording_tracker
      provider = local_provider([flag_definition], tracker, hierarchical_groups: true)

      provider.get_variant_value('hg_flag', fallback, { 'distinct_id' => 'user-123', '$user_id' => 'user-123' })

      identity, _, properties = calls.first
      expect(identity).to eq(Mixpanel::Identity.new(distinct_id: 'user-123'))
      expect(properties['distinct_id']).to eq('user-123')
      expect(properties).not_to have_key('$user_id')
    end

    it 'sends a non-hierarchical exposure exactly as before, ignoring $user_id and $company_id' do
      tracker, calls = recording_tracker
      provider = local_provider([flag_definition], tracker)
      keys = hashed_keys

      provider.get_variant_value('hg_flag', fallback, hg_context.merge('distinct_id' => 'user-123'))

      expect(keys.uniq).to eq(['user-123'])
      expect(calls).to eq([[
        'user-123',
        '$experiment_started',
        {
          'distinct_id' => 'user-123',
          'Experiment name' => 'hg_flag',
          'Variant name' => 'control',
          '$experiment_type' => 'feature_flag',
          'Flag evaluation mode' => 'local',
          '$is_qa_tester' => false
        }
      ]])
      expect(calls.first[2].keys).to eq(['distinct_id', 'Experiment name', 'Variant name', '$experiment_type',
                                         'Flag evaluation mode', '$is_qa_tester'])
    end

    it 'drops a non-hierarchical exposure without distinct_id with the unchanged message' do
      tracker, calls = recording_tracker
      provider = local_provider([flag_definition(context_template: template)], tracker)

      expect(error_handler).to receive(:handle) do |error|
        expect(error.message).to eq("Cannot track exposure event for flag 'hg_flag' without a distinct_id in the context")
      end
      expect(provider.get_variant_value('hg_flag', fallback, hg_context)).to eq('value-a')
      expect(calls).to be_empty
    end
  end

  describe 'remote flags' do
    def remote_provider(tracker, hierarchical_groups: false)
      Mixpanel::Flags::RemoteFlagsProvider.new(test_token, {}, tracker, error_handler,
                                               hierarchical_groups: hierarchical_groups)
    end

    def stub_remote_flags
      stub_request(:get, remote_url_regex)
        .to_return(status: 200,
                   body: { code: 200, flags: { 'hg_flag' => { 'variant_key' => 'control', 'variant_value' => 'value-a' } } }.to_json,
                   headers: { 'Content-Type' => 'application/json' })
    end

    it 'forwards the hierarchical context and sends an exposure with $user_id and $company_id' do
      stub_remote_flags
      tracker, calls = recording_tracker

      expect(remote_provider(tracker, hierarchical_groups: true).get_variant_value('hg_flag', fallback, hg_context))
        .to eq('value-a')

      expect(WebMock).to have_requested(:get, remote_url_regex).with { |request|
        JSON.parse(URI.decode_www_form(request.uri.query).to_h['context']) == hg_context
      }
      identity, _, properties = calls.first
      expect(identity).to eq(Mixpanel::Identity.new(user_id: 'user-123', company_id: 'acme'))
      expect(properties['$user_id']).to eq('user-123')
      expect(properties['$company_id']).to eq('acme')
      expect(properties).not_to have_key('distinct_id')
      expect(properties['Flag evaluation mode']).to eq('remote')
    end

    it 'drops a hierarchical exposure without $company_id or distinct_id' do
      stub_remote_flags
      tracker, calls = recording_tracker

      expect(error_handler).to receive(:handle) do |error|
        expect(error.message).to eq("Cannot track exposure event for flag 'hg_flag' without a $company_id in the context")
      end
      remote_provider(tracker, hierarchical_groups: true).get_variant_value('hg_flag', fallback, { '$user_id' => 'user-123' })
      expect(calls).to be_empty
    end

    it 'sends a non-hierarchical exposure with a distinct_id string as before' do
      stub_remote_flags
      tracker, calls = recording_tracker

      remote_provider(tracker).get_variant_value('hg_flag', fallback, hg_context.merge('distinct_id' => 'user-123'))

      distinct_id, _, properties = calls.first
      expect(distinct_id).to eq('user-123')
      expect(properties.keys.first).to eq('distinct_id')
      expect(properties).not_to have_key('$user_id')
      expect(properties).not_to have_key('$company_id')
    end
  end

  describe 'through the Tracker' do
    def tracker_with_flags(hierarchical_groups)
      messages = []
      tracker = Mixpanel::Tracker.new(test_token, hierarchical_groups: hierarchical_groups,
                                      local_flags_config: { enable_polling: false }) do |type, message|
        messages << [type, JSON.parse(message)]
      end
      [tracker, messages]
    end

    it 'routes a hierarchical exposure through #track with an identity' do
      stub_definitions([flag_definition(context_template: template)])
      tracker, messages = tracker_with_flags(true)
      tracker.local_flags.start_polling_for_definitions!

      expect(tracker.local_flags.get_variant_value('hg_flag', fallback, hg_context)).to eq('value-a')

      expect(messages.size).to eq(1)
      type, message = messages.first
      properties = message['data']['properties']
      expect(type).to eq(:event)
      expect(properties['$user_id']).to eq('user-123')
      expect(properties['$company_id']).to eq('acme')
      expect(properties).not_to have_key('distinct_id')
      expect(properties['token']).to eq(test_token)
    end

    it 'routes a non-hierarchical exposure through #track with the distinct_id' do
      stub_definitions([flag_definition])
      tracker, messages = tracker_with_flags(false)
      tracker.local_flags.start_polling_for_definitions!

      tracker.local_flags.get_variant_value('hg_flag', fallback, hg_context.merge('distinct_id' => 'user-123'))

      properties = messages.first[1]['data']['properties']
      expect(properties['distinct_id']).to eq('user-123')
      expect(properties).not_to have_key('$user_id')
      expect(properties).not_to have_key('$company_id')
    end
  end
end
