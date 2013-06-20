require 'mixpanel-ruby/consumer'
require 'time'

module Mixpanel
  class Events
    def initialize(token, consumer=nil, &block)
      @token = token
      if block
        @sink = block
      elsif consumer
        @sink = consumer.method(:send)
      else
        consumer = Consumer.new
        @sink = consumer.method(:send)
      end
    end

    def track(distinct_id, event, properties={}, ip=nil)
      properties = {
          'distinct_id' => distinct_id,
          'token' => @token,
          'time' => Time.now.to_i
      }.merge(properties)
      if ip
        properties['ip'] = ip
      end

      message = {
          'event' => event,
          'properties' => properties
      }

      @sink.call(:event, message.to_json)
    end

    def alias(alias_id, real_id)
      track(real_id, '$create_alias', {
          'alias' => alias_id
      })
    end
  end
end
