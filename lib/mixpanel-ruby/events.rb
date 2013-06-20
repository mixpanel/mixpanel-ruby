require 'mixpanel-ruby/consumer'

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
      properties = properties.merge({
          'distinct_id' => distinct_id,
          'token' => @token
      })
      if ip
        properties['ip'] = ip
      end

      message = {
          'event' => event,
          'properties' => properties
      }

      @sink.call(:event, message.to_json)
    end

    def alias(aliasId, realId)
      # TODO UNIMPLEMENTED
    end
  end
end
