# lib/mixpanel-ruby/ai_bot_classifier.rb

module Mixpanel
  module AiBotClassifier
    BOT_DATABASE = [
      {
        pattern: /GPTBot\//i,
        name: 'GPTBot',
        provider: 'OpenAI',
        category: 'indexing',
        description: 'OpenAI web crawler for model training data',
      },
      {
        pattern: /ChatGPT-User\//i,
        name: 'ChatGPT-User',
        provider: 'OpenAI',
        category: 'retrieval',
        description: 'ChatGPT real-time retrieval for user queries (RAG)',
      },
      {
        pattern: /OAI-SearchBot\//i,
        name: 'OAI-SearchBot',
        provider: 'OpenAI',
        category: 'indexing',
        description: 'OpenAI search indexing crawler',
      },
      {
        pattern: /ClaudeBot\//i,
        name: 'ClaudeBot',
        provider: 'Anthropic',
        category: 'indexing',
        description: 'Anthropic web crawler for model training',
      },
      {
        pattern: /Claude-User\//i,
        name: 'Claude-User',
        provider: 'Anthropic',
        category: 'retrieval',
        description: 'Claude real-time retrieval for user queries',
      },
      {
        pattern: /Google-Extended\//i,
        name: 'Google-Extended',
        provider: 'Google',
        category: 'indexing',
        description: 'Google AI training data crawler',
      },
      {
        pattern: /PerplexityBot\//i,
        name: 'PerplexityBot',
        provider: 'Perplexity',
        category: 'retrieval',
        description: 'Perplexity AI search crawler',
      },
      {
        pattern: /Bytespider\//i,
        name: 'Bytespider',
        provider: 'ByteDance',
        category: 'indexing',
        description: 'ByteDance/TikTok AI crawler',
      },
      {
        pattern: /CCBot\//i,
        name: 'CCBot',
        provider: 'Common Crawl',
        category: 'indexing',
        description: 'Common Crawl bot',
      },
      {
        pattern: /Applebot-Extended\//i,
        name: 'Applebot-Extended',
        provider: 'Apple',
        category: 'indexing',
        description: 'Apple AI/Siri training data crawler',
      },
      {
        pattern: /Meta-ExternalAgent\//i,
        name: 'Meta-ExternalAgent',
        provider: 'Meta',
        category: 'indexing',
        description: 'Meta/Facebook AI training data crawler',
      },
      {
        pattern: /cohere-ai\//i,
        name: 'cohere-ai',
        provider: 'Cohere',
        category: 'indexing',
        description: 'Cohere AI training data crawler',
      },
    ].freeze

    # Classify a user-agent string against the AI bot database.
    #
    # @param user_agent [String, nil] The user-agent string to classify
    # @return [Hash] Classification result with :is_ai_bot and optional :bot_name, :provider, :category
    def self.classify(user_agent)
      return { is_ai_bot: false } if user_agent.nil? || user_agent.empty?

      BOT_DATABASE.each do |bot|
        if bot[:pattern].match?(user_agent)
          return {
            is_ai_bot: true,
            bot_name: bot[:name],
            provider: bot[:provider],
            category: bot[:category],
          }
        end
      end

      { is_ai_bot: false }
    end

    # Return a copy of the bot database for inspection.
    #
    # @return [Array<Hash>] Array of bot entries
    def self.bot_database
      BOT_DATABASE.map { |bot| bot.slice(:name, :provider, :category, :description) }
    end

    # Create a classifier with optional additional bot patterns.
    #
    # @param additional_bots [Array<Hash>] Additional bot patterns (checked first)
    # @return [Proc] A classifier proc that accepts a user-agent string
    def self.create_classifier(additional_bots: [])
      combined = additional_bots + BOT_DATABASE

      ->(user_agent) {
        return { is_ai_bot: false } if user_agent.nil? || user_agent.empty?

        combined.each do |bot|
          if bot[:pattern].match?(user_agent)
            return {
              is_ai_bot: true,
              bot_name: bot[:name],
              provider: bot[:provider],
              category: bot[:category],
            }
          end
        end

        { is_ai_bot: false }
      }
    end
  end
end
