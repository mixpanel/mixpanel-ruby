# spec/mixpanel-ruby/ai_bot_properties_spec.rb
require 'spec_helper'
require 'mixpanel-ruby'
require 'mixpanel-ruby/ai_bot_properties'
require 'mixpanel-ruby/ai_bot_classifier'

describe Mixpanel::AiBotProperties do
  before(:each) do
    @time_now = Time.parse('Jun 6 1972, 16:23:04')
    allow(Time).to receive(:now).and_return(@time_now)

    @log = []
    @tracker = Mixpanel::Tracker.new('TEST TOKEN') do |type, message|
      @log << [type, JSON.load(message)]
    end
    @tracker.extend(Mixpanel::AiBotProperties)
  end

  after(:each) do
    Thread.current[:mixpanel_bot_classification] = nil
  end

  describe '#track with $user_agent property' do
    it 'enriches events when $user_agent identifies an AI bot' do
      @tracker.track('user123', 'page_view', {
        '$user_agent' => 'Mozilla/5.0 (compatible; GPTBot/1.2; +https://openai.com/gptbot)',
      })

      expect(@log.length).to eq(1)
      type, message = @log[0]
      props = message['data']['properties']

      expect(props['$is_ai_bot']).to be true
      expect(props['$ai_bot_name']).to eq('GPTBot')
      expect(props['$ai_bot_provider']).to eq('OpenAI')
      expect(props['$ai_bot_category']).to eq('indexing')
    end

    it 'sets $is_ai_bot false for non-AI user agents' do
      @tracker.track('user123', 'page_view', {
        '$user_agent' => 'Mozilla/5.0 Chrome/120.0.0.0',
      })

      props = @log[0][1]['data']['properties']
      expect(props['$is_ai_bot']).to be false
      expect(props['$ai_bot_name']).to be_nil
    end

    it 'does not add classification when $user_agent is absent' do
      @tracker.track('user123', 'page_view', { 'page' => '/home' })

      props = @log[0][1]['data']['properties']
      expect(props).not_to have_key('$is_ai_bot')
    end

    it 'preserves existing properties' do
      @tracker.track('user123', 'page_view', {
        '$user_agent' => 'GPTBot/1.2',
        'page_url' => '/products',
        'custom_prop' => 'value',
      })

      props = @log[0][1]['data']['properties']
      expect(props['page_url']).to eq('/products')
      expect(props['custom_prop']).to eq('value')
      expect(props['$is_ai_bot']).to be true
    end

    it 'preserves SDK default properties' do
      @tracker.track('user123', 'page_view', {
        '$user_agent' => 'GPTBot/1.2',
      })

      props = @log[0][1]['data']['properties']
      expect(props['token']).to eq('TEST TOKEN')
      expect(props['distinct_id']).to eq('user123')
      expect(props['mp_lib']).to eq('ruby')
      expect(props['$lib_version']).to eq(Mixpanel::VERSION)
    end

    it 'returns true on success (matches existing track behavior)' do
      result = @tracker.track('user123', 'page_view', {
        '$user_agent' => 'GPTBot/1.2',
      })
      expect(result).to be true
    end

    it 'passes through ip parameter' do
      @tracker.track('user123', 'page_view', {
        '$user_agent' => 'GPTBot/1.2',
      }, '1.2.3.4')

      props = @log[0][1]['data']['properties']
      expect(props['ip']).to eq('1.2.3.4')
      expect(props['$is_ai_bot']).to be true
    end
  end

  describe '#track with Thread.current[:mixpanel_bot_classification]' do
    it 'uses thread-local classification when available' do
      Thread.current[:mixpanel_bot_classification] = {
        is_ai_bot: true,
        bot_name: 'GPTBot',
        provider: 'OpenAI',
        category: 'indexing',
      }

      @tracker.track('user123', 'page_view', { 'page' => '/home' })

      props = @log[0][1]['data']['properties']
      expect(props['$is_ai_bot']).to be true
      expect(props['$ai_bot_name']).to eq('GPTBot')
    end

    it 'prefers $user_agent property over thread-local when both present' do
      Thread.current[:mixpanel_bot_classification] = {
        is_ai_bot: true,
        bot_name: 'GPTBot',
        provider: 'OpenAI',
        category: 'indexing',
      }

      @tracker.track('user123', 'page_view', {
        '$user_agent' => 'ClaudeBot/1.0',
      })

      props = @log[0][1]['data']['properties']
      # $user_agent classification should take priority
      expect(props['$ai_bot_name']).to eq('ClaudeBot')
    end

    it 'adds non-bot classification from thread-local' do
      Thread.current[:mixpanel_bot_classification] = {
        is_ai_bot: false,
      }

      @tracker.track('user123', 'page_view', { 'page' => '/home' })

      props = @log[0][1]['data']['properties']
      expect(props['$is_ai_bot']).to be false
    end
  end

  describe 'multiple bot types' do
    it 'correctly classifies different bots in sequence' do
      bots = [
        ['GPTBot/1.2', 'GPTBot', 'OpenAI'],
        ['ClaudeBot/1.0', 'ClaudeBot', 'Anthropic'],
        ['PerplexityBot/1.0', 'PerplexityBot', 'Perplexity'],
      ]

      bots.each do |ua, name, provider|
        @log.clear
        @tracker.track('user123', 'page_view', { '$user_agent' => ua })
        props = @log[0][1]['data']['properties']
        expect(props['$is_ai_bot']).to be(true), "Failed for #{ua}"
        expect(props['$ai_bot_name']).to eq(name), "Wrong name for #{ua}"
        expect(props['$ai_bot_provider']).to eq(provider), "Wrong provider for #{ua}"
      end
    end
  end
end
