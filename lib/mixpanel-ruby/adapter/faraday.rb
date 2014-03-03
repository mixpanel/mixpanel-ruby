require 'faraday'

module Faraday
  class Response
    alias :code :status unless method_defined?(:code)
  end
end

module Mixpanel
  module Adapter
    module Faraday
      def self.request(endpoint, form_data)
        conn = ::Faraday.new(endpoint)
        Mixpanel.with_http(conn)
        conn.post(nil, form_data)
      end
    end
  end
end
