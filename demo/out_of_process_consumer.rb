require 'mixpanel-ruby'
require 'thread'
require 'json'
require 'securerandom'

# As your application scales, it's likely you'll want to
# to detect events in one place and send them somewhere
# else. For example, you might write the events to a queue
# to be consumed by another process.
#
# This demo shows how you might do things, using
# the block constructor in Mixpanel to enqueue events,
# and a MixpanelBufferedConsumer to send them to
# Mixpanel

# Mixpanel uses the Net::HTTP library, which by default
# will not verify remote SSL certificates. In your app,
# you'll need to call Mixpanel.config_http with the path
# to your Certificate authority resources, or the library
# won't verify the remote certificate identity.
Mixpanel.config_http do |http|
  http.ca_path = '/etc/ssl/certs'
  http.ca_file = "/etc/ssl/certs/ca-certificates.crt"
  http.use_ssl = true
  http.verify_mode = OpenSSL::SSL::VERIFY_PEER
end

class OutOfProcessExample
  class << self
    def run(token, distinct_id)
      open('|-', 'w+') do |subprocess|
        if subprocess
          # This is the tracking process. Once we configure
          # The tracker to write to our subprocess, we can quickly
          # call #track without delaying our other work.
          mixpanel_tracker = Mixpanel::Tracker.new(token) do |*message|
            subprocess.write(message.to_json + "\n")
          end

          100.times do |i|
            event = 'Tick'
            mixpanel_tracker.track(distinct_id, event, {'Tick Number' => i})
            puts "tick #{i}"
          end

        else
          # This is the consumer process. In your applications, code
          # like this may end up in queue consumers or in a separate
          # thread.
          mixpanel_consumer = Mixpanel::BufferedConsumer.new
          begin
            $stdin.each_line do |line|
              message = JSON.load(line)
              type, content = message
              mixpanel_consumer.send!(type, content)
            end
          ensure
            mixpanel_consumer.flush
          end
        end
      end
    end # run
  end
end

if __FILE__ == $0
  # Replace this with the token from your project settings
  DEMO_TOKEN = '072f77c15bd04a5d0044d3d76ced7fea'
  run_id = SecureRandom.base64
  OutOfProcessExample.run(DEMO_TOKEN, run_id)
end
