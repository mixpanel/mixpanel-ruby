require 'mixpanel-ruby/flags/flags_provider'

module Mixpanel
  module Flags
    # Remote feature flags provider
    # Evaluates flags on the server-side via HTTP API calls
    class RemoteFlagsProvider < FlagsProvider
      DEFAULT_CONFIG = {
        api_host: 'api.mixpanel.com',
        request_timeout_in_seconds: 10
      }.freeze

      # @param token [String] Mixpanel project token
      # @param config [Hash] Remote flags configuration
      # @param tracker_callback [Proc] Callback to track events
      # @param error_handler [Mixpanel::ErrorHandler] Error handler
      def initialize(token, config, tracker_callback, error_handler)
        merged_config = DEFAULT_CONFIG.merge(config || {})

        provider_config = {
          token: token,
          api_host: merged_config[:api_host],
          request_timeout_in_seconds: merged_config[:request_timeout_in_seconds]
        }

        super(provider_config, '/flags', tracker_callback, 'remote', error_handler)
      end

      # Get variant value for a flag
      # @param flag_key [String] Feature flag key
      # @param fallback_value [Object] Fallback value
      # @param context [Hash] Evaluation context
      # @param report_exposure [Boolean] Whether to track exposure
      # @return [Object] Variant value
      def get_variant_value(flag_key, fallback_value, context, report_exposure: true)
        selected_variant = get_variant(
          flag_key,
          SelectedVariant.new(variant_value: fallback_value),
          context,
          report_exposure: report_exposure
        )
        selected_variant.variant_value
      rescue MixpanelError => e
        @error_handler.handle(e)
        fallback_value
      end

      # Get complete variant information
      # @param flag_key [String] Feature flag key
      # @param fallback_variant [SelectedVariant] Fallback variant
      # @param context [Hash] Evaluation context
      # @param report_exposure [Boolean] Whether to track exposure
      # @return [SelectedVariant]
      def get_variant(flag_key, fallback_variant, context, report_exposure: true)
        start_time = Time.now
        response = fetch_flags(context, flag_key)
        latency_ms = ((Time.now - start_time) * 1000).to_i

        flags = response['flags'] || {}
        selected_variant_data = flags[flag_key]

        return fallback_variant unless selected_variant_data

        selected_variant = SelectedVariant.new(
          variant_key: selected_variant_data['variant_key'],
          variant_value: selected_variant_data['variant_value'],
          experiment_id: selected_variant_data['experiment_id'],
          is_experiment_active: selected_variant_data['is_experiment_active']
        )

        track_exposure_event(flag_key, selected_variant, context, latency_ms) if report_exposure

        return selected_variant
      rescue MixpanelError => e
        @error_handler.handle(e)
        return fallback_variant
      end

      # Check if flag is enabled (for boolean flags)
      # This method is intended only for flags defined as Mixpanel Feature Gates (boolean flags)
      # This checks that the variant value of a selected variant is concretely the boolean 'true'
      # It does not coerce other truthy values.
      # @param flag_key [String] Feature flag key
      # @param context [Hash] Evaluation context
      # @return [Boolean]
      def is_enabled(flag_key, context)
        value = get_variant_value(flag_key, false, context)
        value == true
      rescue MixpanelError => e
        @error_handler.handle(e)
        false
      end

      # Get all variants for user context
      # Exposure events NOT tracked automatically
      # @param context [Hash] Evaluation context
      # @return [Hash, nil] Map of flag_key => SelectedVariant, or nil on error
      def get_all_variants(context)
        response = fetch_flags(context)

        variants = {}
        (response['flags'] || {}).each do |flag_key, variant_data|
          variants[flag_key] = SelectedVariant.new(
            variant_key: variant_data['variant_key'],
            variant_value: variant_data['variant_value'],
            experiment_id: variant_data['experiment_id'],
            is_experiment_active: variant_data['is_experiment_active']
          )
        end

        variants
      rescue MixpanelError => e
        @error_handler.handle(e)
        nil
      end

      private

      # Fetch flags from remote API
      # @param context [Hash] Evaluation context
      # @param flag_key [String, nil] Optional specific flag key
      # @return [Hash] API response
      def fetch_flags(context, flag_key = nil)
        additional_params = {
          'context' => JSON.generate(context)
        }

        additional_params['flag_key'] = flag_key if flag_key

        call_flags_endpoint(additional_params)
      end
    end
  end
end
