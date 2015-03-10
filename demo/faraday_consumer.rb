require 'mixpanel-ruby'
require 'faraday'

# The Mixpanel library's default consumer will use the standard
# Net::HTTP library to communicate with servers, but you can extend
# your consumers to use other libraries. This example sends data using
# the Faraday library (so you'll need that library available to run it)

class FaradayConsumer < Mixpanel::Consumer
  def request(endpoint, form_data)
    conn = ::Faraday.new(endpoint)
    response = conn.post(nil, form_data)
    [response.status, response.body]
  end
end

if __FILE__ == $0
  # Replace this with the token from your project settings
  DEMO_TOKEN = '072f77c15bd04a5d0044d3d76ced7fea'
  faraday_consumer = FaradayConsumer.new

  faraday_tracker = Mixpanel::Tracker.new(DEMO_TOKEN) do |type, message|
    faraday_consumer.send!(type, message)
  end
  faraday_tracker.track('ID', 'Event tracked through Faraday')

  # It's also easy to delegate from a BufferedConsumer to your custom
  # consumer.

  buffered_faraday_consumer = Mixpanel::BufferedConsumer.new do |type, message|
    faraday_consumer.send!(type, message)
  end

  buffered_faraday_tracker = Mixpanel::Tracker.new(DEMO_TOKEN) do |type, message|
    buffered_faraday_consumer.send!(type, message)
  end

  buffered_faraday_tracker.track('ID', 'Event tracked (buffered) through faraday')
  buffered_faraday_consumer.flush
end
