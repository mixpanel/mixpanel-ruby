require 'net/https'
require 'json'
require 'uri'
require 'mixpanel-ruby/version'
require 'mixpanel-ruby/error'
require 'mixpanel-ruby/flags/utils'
require 'mixpanel-ruby/flags/types'

module Mixpanel
  module Flags

    # Base class for feature flags providers
    # Provides common HTTP handling and exposure event tracking
    class FlagsProvider
      # @param provider_config [Hash] Configuration with :token, :api_host, :request_timeout_in_seconds
      # @param endpoint [String] API endpoint path (e.g., '/flags' or '/flags/definitions')
      # @param tracker_callback [Proc] Function used to track events (bound tracker.track method)
      # @param evaluation_mode [String] The feature flag evaluation mode. This is either 'local' or 'remote'
      # @param error_handler [Mixpanel::ErrorHandler] Error handler instance
      def initialize(provider_config, endpoint, tracker_callback, evaluation_mode, error_handler)
        @provider_config = provider_config
        @endpoint = endpoint
        @tracker_callback = tracker_callback
        @evaluation_mode = evaluation_mode
        @error_handler = error_handler
      end

      # Make HTTP request to flags API endpoint
      # @param additional_params [Hash, nil] Additional query parameters
      # @return [Hash] Parsed JSON response
      # @raise [Mixpanel::ConnectionError] on network errors
      # @raise [Mixpanel::ServerError] on HTTP errors
      def call_flags_endpoint(additional_params = nil)
        common_params = Utils.prepare_common_query_params(
          @provider_config[:token],
          Mixpanel::VERSION
        )

        params = common_params.merge(additional_params || {})
        query_string = URI.encode_www_form(params)

        uri = URI::HTTPS.build(
          host: @provider_config[:api_host],
          path: @endpoint,
          query: query_string
        )

        http = Net::HTTP.new(uri.host, uri.port)

        http.use_ssl = true
        http.open_timeout = @provider_config[:request_timeout_in_seconds]
        http.read_timeout = @provider_config[:request_timeout_in_seconds]

        request = Net::HTTP::Get.new(uri.request_uri)

        request.basic_auth(@provider_config[:token], '')

        request['Content-Type'] = 'application/json'
        request['traceparent'] = Utils.generate_traceparent()

        begin
          response = http.request(request)

          unless response.code.to_i == 200
            raise ServerError.new("HTTP #{response.code}: #{response.body}")
          end

          JSON.parse(response.body)
        rescue Net::OpenTimeout, Net::ReadTimeout => e
          raise ConnectionError.new("Request timeout: #{e.message}")
        rescue JSON::ParserError => e
          raise ServerError.new("Invalid JSON response: #{e.message}")
        rescue StandardError => e
          raise ConnectionError.new("Network error: #{e.message}")
        end
      end

      # Track exposure event to Mixpanel
      # @param flag_key [String] Feature flag key
      # @param selected_variant [SelectedVariant] The selected variant
      # @param context [Hash] User context (must include 'distinct_id')
      # @param latency_ms [Integer, nil] Optional latency in milliseconds
      def track_exposure_event(flag_key, selected_variant, context, latency_ms = nil)
        distinct_id = context['distinct_id'] || context[:distinct_id]

        unless distinct_id
          return
        end

        properties = {
          'distinct_id' => distinct_id,
          'Experiment name' => flag_key,
          'Variant name' => selected_variant.variant_key,
          '$experiment_type' => 'feature_flag',
          'Flag evaluation mode' => @evaluation_mode
        }

        properties['Variant fetch latency (ms)'] = latency_ms if latency_ms
        properties['$experiment_id'] = selected_variant.experiment_id if selected_variant.experiment_id
        properties['$is_experiment_active'] = selected_variant.is_experiment_active unless selected_variant.is_experiment_active.nil?
        properties['$is_qa_tester'] = selected_variant.is_qa_tester unless selected_variant.is_qa_tester.nil?

        begin
          @tracker_callback.call(distinct_id, Utils::EXPOSURE_EVENT, properties)
        rescue MixpanelError => e
          @error_handler.handle(e)
        end
      end
    end
  end
end
