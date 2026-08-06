# lib/mixpanel-ruby/ai_bot_properties.rb

require_relative 'ai_bot_classifier'

module Mixpanel
  # Module mixin for Tracker that enriches track() calls with AI bot
  # classification properties.
  #
  # Uses two sources (in priority order):
  # 1. '$user_agent' property in the event properties (direct classification)
  # 2. Thread.current[:mixpanel_bot_classification] (from Rack middleware)
  #
  # Usage:
  #   tracker = Mixpanel::Tracker.new(token)
  #   tracker.extend(Mixpanel::AiBotProperties)
  #   tracker.track(distinct_id, event, {'$user_agent' => request.user_agent})
  #
  module AiBotProperties
    def track(distinct_id, event, properties = {}, ip = nil)
      classification = nil

      # Priority 1: Classify from $user_agent property
      if properties['$user_agent']
        classification = AiBotClassifier.classify(properties['$user_agent'])
      # Priority 2: Use thread-local from Rack middleware
      elsif Thread.current[:mixpanel_bot_classification]
        classification = Thread.current[:mixpanel_bot_classification]
      end

      if classification
        properties = properties.merge(
          classification_to_properties(classification)
        )
      end

      super(distinct_id, event, properties, ip)
    end

    private

    def classification_to_properties(classification)
      props = { '$is_ai_bot' => classification[:is_ai_bot] }
      if classification[:is_ai_bot]
        props['$ai_bot_name'] = classification[:bot_name]
        props['$ai_bot_provider'] = classification[:provider]
        props['$ai_bot_category'] = classification[:category]
      end
      props
    end
  end
end
