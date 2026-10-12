# spec/mixpanel-ruby/ai_bot_classifier_spec.rb
require 'spec_helper'
require 'mixpanel-ruby/ai_bot_classifier'

describe Mixpanel::AiBotClassifier do

  describe '.classify' do

    # === OpenAI Bots ===

    it 'classifies GPTBot user agent' do
      result = described_class.classify(
        'Mozilla/5.0 AppleWebKit/537.36 (KHTML, like Gecko; compatible; ' \
        'GPTBot/1.2; +https://openai.com/gptbot)'
      )
      expect(result[:is_ai_bot]).to be true
      expect(result[:bot_name]).to eq('GPTBot')
      expect(result[:provider]).to eq('OpenAI')
      expect(result[:category]).to eq('indexing')
    end

    it 'classifies ChatGPT-User agent' do
      result = described_class.classify(
        'Mozilla/5.0 AppleWebKit/537.36 (KHTML, like Gecko; compatible; ' \
        'ChatGPT-User/1.0; +https://openai.com/bot)'
      )
      expect(result[:is_ai_bot]).to be true
      expect(result[:bot_name]).to eq('ChatGPT-User')
      expect(result[:provider]).to eq('OpenAI')
      expect(result[:category]).to eq('retrieval')
    end

    it 'classifies OAI-SearchBot agent' do
      result = described_class.classify(
        'Mozilla/5.0 (compatible; OAI-SearchBot/1.0; +https://openai.com/searchbot)'
      )
      expect(result[:is_ai_bot]).to be true
      expect(result[:bot_name]).to eq('OAI-SearchBot')
      expect(result[:provider]).to eq('OpenAI')
      expect(result[:category]).to eq('indexing')
    end

    # === Anthropic Bots ===

    it 'classifies ClaudeBot agent' do
      result = described_class.classify(
        'Mozilla/5.0 (compatible; ClaudeBot/1.0; +claudebot@anthropic.com)'
      )
      expect(result[:is_ai_bot]).to be true
      expect(result[:bot_name]).to eq('ClaudeBot')
      expect(result[:provider]).to eq('Anthropic')
      expect(result[:category]).to eq('indexing')
    end

    it 'classifies Claude-User agent' do
      result = described_class.classify('Mozilla/5.0 (compatible; Claude-User/1.0)')
      expect(result[:is_ai_bot]).to be true
      expect(result[:bot_name]).to eq('Claude-User')
      expect(result[:provider]).to eq('Anthropic')
      expect(result[:category]).to eq('retrieval')
    end

    # === Google ===

    it 'classifies Google-Extended agent' do
      result = described_class.classify('Mozilla/5.0 (compatible; Google-Extended/1.0)')
      expect(result[:is_ai_bot]).to be true
      expect(result[:bot_name]).to eq('Google-Extended')
      expect(result[:provider]).to eq('Google')
      expect(result[:category]).to eq('indexing')
    end

    # === Perplexity ===

    it 'classifies PerplexityBot agent' do
      result = described_class.classify('Mozilla/5.0 (compatible; PerplexityBot/1.0)')
      expect(result[:is_ai_bot]).to be true
      expect(result[:bot_name]).to eq('PerplexityBot')
      expect(result[:provider]).to eq('Perplexity')
      expect(result[:category]).to eq('retrieval')
    end

    # === ByteDance ===

    it 'classifies Bytespider agent' do
      result = described_class.classify('Mozilla/5.0 (compatible; Bytespider/1.0)')
      expect(result[:is_ai_bot]).to be true
      expect(result[:bot_name]).to eq('Bytespider')
      expect(result[:provider]).to eq('ByteDance')
    end

    # === Common Crawl ===

    it 'classifies CCBot agent' do
      result = described_class.classify('CCBot/2.0 (https://commoncrawl.org/faq/)')
      expect(result[:is_ai_bot]).to be true
      expect(result[:bot_name]).to eq('CCBot')
      expect(result[:provider]).to eq('Common Crawl')
    end

    # === Apple ===

    it 'classifies Applebot-Extended agent' do
      result = described_class.classify(
        'Mozilla/5.0 (Macintosh; Intel Mac OS X) ' \
        'AppleWebKit/605.1.15 (KHTML, like Gecko) Applebot-Extended/0.1'
      )
      expect(result[:is_ai_bot]).to be true
      expect(result[:bot_name]).to eq('Applebot-Extended')
      expect(result[:provider]).to eq('Apple')
    end

    # === Meta ===

    it 'classifies Meta-ExternalAgent' do
      result = described_class.classify('Mozilla/5.0 (compatible; Meta-ExternalAgent/1.0)')
      expect(result[:is_ai_bot]).to be true
      expect(result[:bot_name]).to eq('Meta-ExternalAgent')
      expect(result[:provider]).to eq('Meta')
    end

    # === Cohere ===

    it 'classifies cohere-ai agent' do
      result = described_class.classify('cohere-ai/1.0 (https://cohere.com)')
      expect(result[:is_ai_bot]).to be true
      expect(result[:bot_name]).to eq('cohere-ai')
      expect(result[:provider]).to eq('Cohere')
      expect(result[:category]).to eq('indexing')
    end

    # === NEGATIVE CASES ===

    it 'does not classify regular Chrome as AI bot' do
      result = described_class.classify(
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 ' \
        '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
      )
      expect(result[:is_ai_bot]).to be false
      expect(result[:bot_name]).to be_nil
    end

    it 'does not classify regular Googlebot as AI bot' do
      result = described_class.classify(
        'Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)'
      )
      expect(result[:is_ai_bot]).to be false
    end

    it 'does not classify regular Bingbot as AI bot' do
      result = described_class.classify(
        'Mozilla/5.0 (compatible; bingbot/2.0; +http://www.bing.com/bingbot.htm)'
      )
      expect(result[:is_ai_bot]).to be false
    end

    it 'does not classify curl as AI bot' do
      result = described_class.classify('curl/7.64.1')
      expect(result[:is_ai_bot]).to be false
    end

    it 'handles empty string' do
      result = described_class.classify('')
      expect(result[:is_ai_bot]).to be false
    end

    it 'handles nil' do
      result = described_class.classify(nil)
      expect(result[:is_ai_bot]).to be false
    end

    # === CASE SENSITIVITY ===

    it 'matches case-insensitively' do
      result = described_class.classify('mozilla/5.0 (compatible; gptbot/1.2)')
      expect(result[:is_ai_bot]).to be true
      expect(result[:bot_name]).to eq('GPTBot')
    end

    # === RETURN SHAPE ===

    it 'returns all expected fields for a match' do
      result = described_class.classify('GPTBot/1.2')
      expect(result).to have_key(:is_ai_bot)
      expect(result).to have_key(:bot_name)
      expect(result).to have_key(:provider)
      expect(result).to have_key(:category)
      expect(%w[indexing retrieval agent]).to include(result[:category])
    end

    it 'returns only is_ai_bot for non-matches' do
      result = described_class.classify('Chrome/120')
      expect(result.keys).to eq([:is_ai_bot])
      expect(result[:is_ai_bot]).to be false
    end
  end

  describe '.bot_database' do
    it 'returns an array of bot entries' do
      db = described_class.bot_database
      expect(db).to be_an(Array)
      expect(db.length).to be > 0
    end

    it 'has required fields on each entry' do
      described_class.bot_database.each do |entry|
        expect(entry).to have_key(:name)
        expect(entry).to have_key(:provider)
        expect(entry).to have_key(:category)
      end
    end
  end

  describe '.create_classifier' do
    it 'allows adding custom bot patterns' do
      classifier = described_class.create_classifier(
        additional_bots: [
          {
            pattern: /MyCustomBot\//i,
            name: 'MyCustomBot',
            provider: 'CustomCorp',
            category: 'indexing',
          }
        ]
      )
      result = classifier.call('Mozilla/5.0 (compatible; MyCustomBot/1.0)')
      expect(result[:is_ai_bot]).to be true
      expect(result[:bot_name]).to eq('MyCustomBot')
    end

    it 'checks custom bots before built-in bots' do
      classifier = described_class.create_classifier(
        additional_bots: [
          {
            pattern: /GPTBot\//i,
            name: 'GPTBot-Custom',
            provider: 'CustomProvider',
            category: 'retrieval',
          }
        ]
      )
      result = classifier.call('GPTBot/1.2')
      expect(result[:bot_name]).to eq('GPTBot-Custom')
    end
  end
end
