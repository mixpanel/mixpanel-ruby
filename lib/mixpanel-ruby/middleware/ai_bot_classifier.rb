# lib/mixpanel-ruby/middleware/ai_bot_classifier.rb

require_relative '../ai_bot_classifier'

module Mixpanel
  module Middleware
    # Rack middleware that classifies incoming HTTP requests for AI bot
    # detection and stores the result for downstream Mixpanel tracking.
    #
    # Classification is stored in:
    # - env['mixpanel.bot_classification'] (Rack convention)
    # - Thread.current[:mixpanel_bot_classification] (for Tracker access)
    #
    # Usage:
    #   # In config.ru:
    #   use Mixpanel::Middleware::AiBotClassifier
    #
    #   # In Rails application.rb:
    #   config.middleware.use Mixpanel::Middleware::AiBotClassifier
    #
    class AiBotClassifier
      def initialize(app, options = {})
        @app = app
        @classifier = if options[:additional_bots]
          Mixpanel::AiBotClassifier.create_classifier(
            additional_bots: options[:additional_bots]
          )
        else
          Mixpanel::AiBotClassifier.method(:classify)
        end
      end

      def call(env)
        user_agent = env['HTTP_USER_AGENT']
        ip = extract_ip(env)

        classification = @classifier.call(user_agent)

        classification[:ip] = ip
        classification[:user_agent] = user_agent

        env['mixpanel.bot_classification'] = classification
        Thread.current[:mixpanel_bot_classification] = classification

        begin
          @app.call(env)
        ensure
          Thread.current[:mixpanel_bot_classification] = nil
        end
      end

      private

      def extract_ip(env)
        forwarded = env['HTTP_X_FORWARDED_FOR']
        if forwarded && !forwarded.empty?
          forwarded.split(',').first.strip
        else
          env['REMOTE_ADDR']
        end
      end
    end
  end
end
