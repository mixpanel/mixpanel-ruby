require 'mixpanel/consumer.rb'

class MixpanelEvents
  def initialize(token, consumer=nil)
    @token = token
    @consumer = consumer || MixpanelConsumer.new
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

    @consumer.send_event(message.to_json)
  end

  def alias(aliasId, realId)
  end
end
