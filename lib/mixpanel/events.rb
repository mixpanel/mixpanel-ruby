class MixpanelEvents
  def initialize(token, options={})
    @token = token
    @options = options
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

    @options[:consumer].send_events(message.to_json)
  end

  def alias(aliasId, realId)
  end
end
