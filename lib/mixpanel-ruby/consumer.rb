require 'base64'
require 'net/https'

module Mixpanel
  class ConnectionError < IOError
  end

  @@init_http = nil

  # Ruby's default SSL does not verify the server certificate.
  # To verify a certificate, or install a proxy, pass a block
  # to Mixpanel::use_ssl that configures the Net::HTTP object.
  # For example, if running in Ubuntu Linux, you can run
  #
  #    Mixpanel::use_ssl do |http|
  #        http.ca_path = '/etc/ssl/certs'
  #        http.ca_file = '/etc/ssl/certs/ca-certificates.crt'
  #        http.verify_mode = OpenSSL::SSL::VERIFY_PEER
  #    end
  def self.config_http(&block)
    @@init_http = block
  end

  # Simple, unbuffered, synchronous consumer. Every call
  # to send_profile_update or send_event will send a blocking
  # POST to the mixpanel sevice.
  class Consumer
    def initialize(events_endpoint=nil, update_endpoint=nil)
      @events_endpoint = events_endpoint || 'https://api.mixpanel.com/track'
      @update_endpoint = update_endpoint || 'https://api.mixpanel.com/engage'
    end

    # Send the given string message to Mixpanel. Type should be
    # one of :event or :profile_update, which will determine the endpoint.
    def send(type, message)
      type = type.to_sym
      endpoint = {
        :event => @events_endpoint,
        :profile_update => @update_endpoint,
      }[ type ]
      data = Base64.strict_encode64(message)
      uri = URI(endpoint)

      client = Net::HTTP.new(uri.host, uri.port)
      client.use_ssl = true
      Mixpanel.with_http(client)

      request = Net::HTTP::Post.new(uri.request_uri)
      request.set_form_data({"data" => data })
      response = client.request(request)

      if response.code == '200' and response.body == '1'
        return true
      else
        raise ConnectionError.new('Could not write to Mixpanel')
      end
    end
  end

  # Buffers messages in memory, and sends messages as a batch.
  # This can improve performance, but calls to #send may
  # still block if the buffer is full.
  # If you use this consumer, you should call #flush when
  # your application exits or the messages remaining in the
  # buffer will not be sent.
  class BufferedConsumer
    MAX_LENGTH = 50

    def initialize(events_endpoint=nil, update_endpoint=nil, max_buffer_length=MAX_LENGTH)
      @max_length = [ max_buffer_length, MAX_LENGTH ].min
      @consumer = Consumer.new(events_endpoint, update_endpoint)
      @buffers = {
        :event => [],
        :profile_update => [],
      }
    end

    def send(type, message)
      type = type.to_sym
      @buffers[type] << message
      if @buffers[type].length >= @max_length
        flush_type(type)
      end
    end

    def flush
      @buffers.keys.each { |k| flush_type(k) }
    end

    private

    def flush_type(type)
      @buffers[type].each_slice(@max_length) do |chunk|
        message = "[ #{chunk.join(',')} ]"
        @consumer.send(type, message)
      end
      @buffers[type] = []
    end
  end

  private
  def self.with_http(http)
    if @@init_http
      @@init_http.call(http)
    end
  end
end
