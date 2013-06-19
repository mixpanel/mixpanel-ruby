require 'base64'
require 'net/https'

# Simple, unbuffered, synchronous consumer. Every call
# to send_profile_update or send_event will send a blocking
# POST to the mixpanel sevice.
class MixpanelConsumer
  def initialize(events_endpoint=nil, update_endpoint=nil)
    @events_endpoint = events_endpoint || 'https://api.mixpanel.com/track'
    @update_endpoint = update_endpoint || 'https://api.mixpanel.com/engage'
  end

  def send(type, message)
    endpoint = {
      :event => @events_endpoint,
      :profile_update => @update_endpoint,
    }[ type ]
    data = Base64.strict_encode64(message)
    request = URI(endpoint)
    Net::HTTP.post_form(request, {"data" => data })
  end
end
