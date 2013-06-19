require 'base64'
require 'net/https'

class MixpanelConsumer
  def initialize(events_endpoint=nil, people_endpoint=nil)
    @events_endpoint = events_endpoint || 'https://api.mixpanel.com/track'
    @people_endpoint = people_endpoint || 'https://api.mixpanel.com/engage'
  end

  def send_profile_update(message)
    data = Base64.strict_encode64(message)
    request = URI(@people_endpoint)
    Net::HTTP.post_form(request, {"data" => data})
  end

  def send_event(message)
    data = Base64.strict_encode64(message)
    request = URI(@events_endpoint)
    Net::HTTP.post_form(request, {"data" => data })
  end
end
