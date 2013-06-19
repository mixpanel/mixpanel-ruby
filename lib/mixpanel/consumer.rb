require 'base64'
require 'net/https'

# Simple, unbuffered, synchronous consumer. Every call
# to send_profile_update or send_event will send a blocking
# POST to the mixpanel sevice.
class MixpanelConsumer
  def initialize(events_endpoint=nil, people_endpoint=nil)
    @events_endpoint = events_endpoint || 'https://api.mixpanel.com/track'
    @people_endpoint = people_endpoint || 'https://api.mixpanel.com/engage'
  end

  # Sends a message to the mixpanel people update endpoint
  def send_profile_update(message)
    data = Base64.strict_encode64(message)
    request = URI(@people_endpoint)
    Net::HTTP.post_form(request, {"data" => data})
  end

  # Sends a message to the mixpanel event tracking endpoint
  def send_event(message)
    data = Base64.strict_encode64(message)
    request = URI(@events_endpoint)
    Net::HTTP.post_form(request, {"data" => data })
  end
end
