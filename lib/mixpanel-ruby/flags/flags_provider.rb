require 'net/https'
require 'json'
require 'uri'
require 'mixpanel-ruby/version'
require 'mixpanel-ruby/error'
require 'mixpanel-ruby/identity'
require 'mixpanel-ruby/flags/utils'
require 'mixpanel-ruby/flags/types'

module Mixpanel
  module Flags

    # Base class for feature flags providers
    # Provides common HTTP handling and exposure event tracking
    class FlagsProvider
      # @param provider_config [Hash] Configuration with :token, :api_host, :request_timeout_in_seconds, :exposure_executor, :credentials (optional), :hierarchical_groups (optional)
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
        @exposure_executor = provider_config[:exposure_executor]
        @credentials = provider_config[:credentials]
        @hierarchical_groups = provider_config[:hierarchical_groups] ? true : false
      end

      # Make HTTP request to flags API endpoint
      # @param additional_params [Hash, nil] Additional query parameters
      # @return [Hash] Parsed JSON response
      # @raise [Mixpanel::ConnectionError] on network errors
      # @raise [Mixpanel::ServerError] on HTTP errors
      def call_flags_endpoint(additional_params = nil)
        # Always use token in query params
        common_params = Utils.prepare_common_query_params(
          @provider_config[:token],
          Mixpanel::VERSION
        )

        params = common_params.merge(additional_params || {})

        # Add project_id as query parameter when using service account credentials
        # Note: project_id is required for service account auth but not used for token auth
        if @credentials
          params['project_id'] = @credentials.project_id
        end

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

        # Use service account credentials for basic auth if provided, otherwise use token
        if @credentials
          request.basic_auth(@credentials.username, @credentials.secret)
        else
          request.basic_auth(@provider_config[:token], '')
        end

        request['Content-Type'] = 'application/json'
        request['traceparent'] = Utils.generate_traceparent

        begin
          response = http.request(request)
        rescue Net::OpenTimeout, Net::ReadTimeout => e
          raise ConnectionError.new("Request timeout: #{e.message}")
        rescue StandardError => e
          raise ConnectionError.new("Network error: #{e.message}")
        end

        unless response.code == '200'
          raise ServerError.new("HTTP #{response.code}: #{response.body}")
        end

        begin
          JSON.parse(response.body)
        rescue JSON::ParserError => e
          raise ServerError.new("Invalid JSON response: #{e.message}")
        end
      end

      def shutdown; end

      # Track exposure event to Mixpanel
      # @param flag_key [String] Feature flag key
      # @param selected_variant [SelectedVariant] The selected variant
      # @param context [Hash] User context (must include 'distinct_id')
      # @param latency_ms [Integer, nil] Optional latency in milliseconds
      def track_exposure_event(flag_key, selected_variant, context, latency_ms = nil)
        distinct_id = context['distinct_id'] || context[:distinct_id]

        unless can_attribute_exposure(context)
          # Local eval succeeds when the flag's Variant Assignment Key is
          # something other than distinct_id (e.g., device_id), but the
          # exposure event still needs distinct_id ($company_id for
          # hierarchical groups) to attribute the user. Surface the drop
          # instead of silently returning so callers can see what to include
          # in the context.
          @error_handler&.handle(MixpanelError.new(
            "Cannot track exposure event for flag '#{flag_key}' without a #{@hierarchical_groups ? '$company_id' : 'distinct_id'} in the context"
          ))
          return
        end

        recipient = distinct_id
        if @hierarchical_groups
          # Sent as a Mixpanel::Identity, so the event carries whichever of
          # distinct_id, $user_id and $company_id the context has, and no
          # distinct_id when it has none.
          recipient = hierarchical_exposure_identity(context)
          properties = recipient.to_properties
        else
          properties = { 'distinct_id' => distinct_id }
        end

        properties.merge!(
          'Experiment name' => flag_key,
          'Variant name' => selected_variant.variant_key,
          '$experiment_type' => 'feature_flag',
          'Flag evaluation mode' => @evaluation_mode
        )

        properties['Variant fetch latency (ms)'] = latency_ms if latency_ms
        properties['$experiment_id'] = selected_variant.experiment_id if selected_variant.experiment_id
        properties['$is_experiment_active'] = selected_variant.is_experiment_active unless selected_variant.is_experiment_active.nil?
        properties['$is_qa_tester'] = selected_variant.is_qa_tester unless selected_variant.is_qa_tester.nil?

        dispatch_exposure(recipient, properties)
      end

      private

      # True if an exposure event for this context can be attributed: by
      # distinct_id, or on a hierarchical groups project by $company_id as
      # well, from which Mixpanel builds the distinct id.
      def can_attribute_exposure(context)
        unless @hierarchical_groups
          return context['distinct_id'] || context[:distinct_id] ? true : false
        end

        present?(context_value(context, '$company_id')) || present?(context_value(context, 'distinct_id'))
      end

      def hierarchical_exposure_identity(context)
        distinct_id = context_value(context, 'distinct_id')
        user_id = context_value(context, '$user_id')
        company_id = context_value(context, '$company_id')
        distinct_id = nil unless present?(distinct_id)
        company_id = nil unless present?(company_id)
        user_id = nil unless present?(user_id)

        Mixpanel::Identity.new(distinct_id: exposure_id(distinct_id), user_id: exposure_id(user_id),
                               company_id: exposure_id(company_id))
      end

      # A context value as an identity id: Strings and Integers as given,
      # anything else as its string form, so an exposure is not lost to a
      # context value Mixpanel::Identity does not accept.
      def exposure_id(value)
        value.nil? || value.is_a?(String) || value.is_a?(Integer) ? value : value.to_s
      end

      def context_value(context, key)
        value = context[key]
        value.nil? ? context[key.to_sym] : value
      end

      def present?(value)
        !value.nil? && !value.to_s.empty?
      end

      # Dispatch the tracker call inline or via the configured executor.
      # The executor is duck-typed — anything that responds to #post(&block)
      # works (Concurrent::ExecutorService, or a Thread.new wrapper).
      #
      # Async path only: catch any non-MixpanelError from the tracker so it
      # doesn't terminate the executor thread silently. Inline path
      # preserves the original behavior — non-MixpanelError propagates to
      # the flag evaluator's caller unchanged.
      #
      # distinct_id is a Mixpanel::Identity on a hierarchical groups project.
      def dispatch_exposure(distinct_id, properties)
        if @exposure_executor
          begin
            @exposure_executor.post do
              invoke_tracker(distinct_id, properties)
            rescue StandardError => e
              @error_handler.handle(MixpanelError.new("Exposure event failed: #{e.class}: #{e.message}")) if @error_handler
            end
          rescue StandardError => e
            @error_handler.handle(MixpanelError.new("Exposure event dropped — executor refused to accept task: #{e.message}")) if @error_handler
          end
        else
          invoke_tracker(distinct_id, properties)
        end
      end

      def invoke_tracker(distinct_id, properties)
        @tracker_callback.call(distinct_id, Utils::EXPOSURE_EVENT, properties)
      rescue MixpanelError => e
        @error_handler.handle(e) if @error_handler
      end
    end
  end
end
