module Mixpanel
  module Adapter
    module NetHttp
      def self.request(endpoint, form_data)
        uri = URI(endpoint)
        request = Net::HTTP::Post.new(uri.request_uri)
        request.set_form_data(form_data)

        client = Net::HTTP.new(uri.host, uri.port)
        client.use_ssl = true
        Mixpanel.with_http(client)

        client.request(request)
      end
    end
  end
end
