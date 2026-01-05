require 'thread'
require 'json_logic'
require 'mixpanel-ruby/flags/flags_provider'

module Mixpanel
  module Flags
    # Local feature flags provider
    # Evaluates flags client-side with cached flag definitions
    class LocalFlagsProvider < FlagsProvider
      DEFAULT_CONFIG = {
        api_host: 'api.mixpanel.com',
        request_timeout_in_seconds: 10,
        enable_polling: true,
        polling_interval_in_seconds: 60
      }.freeze

      # @param token [String] Mixpanel project token
      # @param config [Hash] Local flags configuration
      # @param tracker_callback [Proc] Callback to track events
      # @param error_handler [Mixpanel::ErrorHandler] Error handler
      def initialize(token, config, tracker_callback, error_handler)
        @config = DEFAULT_CONFIG.merge(config || {})

        provider_config = {
          token: token,
          api_host: @config[:api_host],
          request_timeout_in_seconds: @config[:request_timeout_in_seconds]
        }

        super(provider_config, '/flags/definitions', tracker_callback, 'local', error_handler)

        @flag_definitions = {}
        @polling_thread = nil
        @stop_polling = false
      end

      # Start polling for flag definitions
      # Fetches immediately, then at regular intervals if polling enabled
      def start_polling_for_definitions!
        fetch_flag_definitions

        if @config[:enable_polling] && !@polling_thread
          @stop_polling = false
          @polling_thread = Thread.new do
            loop do
              sleep @config[:polling_interval_in_seconds]
              break if @stop_polling

              begin
                fetch_flag_definitions
              rescue StandardError => e
                @error_handler.handle(e) if @error_handler
              end
            end
          end
        end
      rescue StandardError => e
        @error_handler.handle(e) if @error_handler
      end

      def stop_polling_for_definitions!
        @stop_polling = true
        @polling_thread&.join
        @polling_thread = nil
      end

      # Check if flag is enabled (for boolean flags)
      # @param flag_key [String] Feature flag key
      # @param context [Hash] Evaluation context (must include 'distinct_id')
      # @return [Boolean]
      def is_enabled?(flag_key, context)
        value = get_variant_value(flag_key, false, context)
        value == true
      end

      # Get variant value for a flag
      # @param flag_key [String] Feature flag key
      # @param fallback_value [Object] Fallback value if not in rollout
      # @param context [Hash] Evaluation context
      # @param report_exposure [Boolean] Whether to track exposure event
      # @return [Object] The variant value
      def get_variant_value(flag_key, fallback_value, context, report_exposure: true)
        result = get_variant(
          flag_key,
          SelectedVariant.new(variant_value: fallback_value),
          context,
          report_exposure: report_exposure
        )
        result.variant_value
      end

      # Get complete variant information
      # @param flag_key [String] Feature flag key
      # @param fallback_variant [SelectedVariant] Fallback variant
      # @param context [Hash] Evaluation context
      # @param report_exposure [Boolean] Whether to track exposure event
      # @return [SelectedVariant]
      def get_variant(flag_key, fallback_variant, context, report_exposure: true)
        flag = @flag_definitions[flag_key]

        return fallback_variant unless flag

        context_key = flag['context']
        unless context.key?(context_key) || context.key?(context_key.to_sym)
          return fallback_variant
        end

        context_value = context[context_key] || context[context_key.to_sym]

        selected_variant = nil

        test_variant = get_variant_override_for_test_user(flag, context)
        if test_variant
          selected_variant = test_variant
        else
          rollout = get_assigned_rollout(flag, context_value, context)
          if rollout
            selected_variant = get_assigned_variant(flag, context_value, flag_key, rollout)
          end
        end

        if selected_variant
          track_exposure_event(flag_key, selected_variant, context) if report_exposure
          return selected_variant
        end

        fallback_variant
      end

      # Get all variants for user context
      # Exposure events NOT tracked automatically
      # @param context [Hash] Evaluation context
      # @return [Hash] Map of flag_key => SelectedVariant
      def get_all_variants(context)
        variants = {}

        @flag_definitions.each_key do |flag_key|
          variant = get_variant(flag_key, nil, context, report_exposure: false)
          variants[flag_key] = variant if variant
        end

        variants
      end

      private

      def fetch_flag_definitions
        response = call_flags_endpoint

        new_definitions = {}
        (response['flags'] || []).each do |flag_data|
          new_definitions[flag_data['key']] = flag_data
        end

        @flag_definitions = new_definitions

        response
      end

      def get_variant_override_for_test_user(flag, context)
        test_users = flag.dig('ruleset', 'test', 'users')
        return nil unless test_users

        distinct_id = context['distinct_id'] || context[:distinct_id]
        return nil unless distinct_id

        variant_key = test_users[distinct_id.to_s]
        return nil unless variant_key

        variant = get_matching_variant(variant_key, flag)
        if variant
          variant.is_qa_tester = true
        end
        variant
      end

      def get_matching_variant(variant_key, flag)
        return nil unless flag['ruleset'] && flag['ruleset']['variants']

        flag['ruleset']['variants'].each do |v|
          if variant_key.downcase == v['key'].downcase
            return SelectedVariant.new(
              variant_key: v['key'],
              variant_value: v['value'],
              experiment_id: flag['experiment_id'],
              is_experiment_active: flag['is_experiment_active']
            )
          end
        end
        nil
      end

      def get_assigned_rollout(flag, context_value, context)
        return nil unless flag['ruleset'] && flag['ruleset']['rollout']

        flag['ruleset']['rollout'].each_with_index do |rollout, index|
          salt = if flag['hash_salt']
                   "#{flag['key']}#{flag['hash_salt']}#{index}"
                 else
                   "#{flag['key']}rollout"
                 end

          rollout_hash = Utils.normalized_hash(context_value.to_s, salt)

          if rollout_hash < rollout['rollout_percentage'] &&
             is_runtime_evaluation_satisfied?(rollout, context)
            return rollout
          end
        end

        nil
      end

      def get_assigned_variant(flag, context_value, flag_key, rollout)
        if rollout['variant_override']
          variant = get_matching_variant(rollout['variant_override']['key'], flag)
          if variant
            variant.is_qa_tester = false
            return variant
          end
        end

        stored_salt = flag['hash_salt'] || ''
        salt = "#{flag_key}#{stored_salt}variant"
        variant_hash = Utils.normalized_hash(context_value.to_s, salt)

        variants = flag['ruleset']['variants'].map { |v| v.dup }
        if rollout['variant_splits']
          variants.each do |v|
            v['split'] = rollout['variant_splits'][v['key']] if rollout['variant_splits'].key?(v['key'])
          end
        end

        selected = variants.first
        cumulative = 0.0
        variants.each do |v|
          selected = v
          cumulative += (v['split'] || 0.0)
          break if variant_hash < cumulative
        end

        SelectedVariant.new(
          variant_key: selected['key'],
          variant_value: selected['value'],
          experiment_id: flag['experiment_id'],
          is_experiment_active: flag['is_experiment_active'],
          is_qa_tester: false
        )
      end

      def lowercase_keys_and_values(val)
        case val
        when String
          val.downcase
        when Array
          val.map { |item| lowercase_keys_and_values(item) }
        when Hash
          val.transform_keys { |k| k.is_a?(String) ? k.downcase : k }
             .transform_values { |v| lowercase_keys_and_values(v) }
        else
          val
        end
      end

      def lowercase_only_leaf_nodes(val)
        case val
        when String
          val.downcase
        when Array
          val.map { |item| lowercase_only_leaf_nodes(item) }
        when Hash
          val.transform_values { |v| lowercase_only_leaf_nodes(v) }
        else
          val
        end
      end

      def get_runtime_parameters(context)
        custom_props = context['custom_properties'] || context[:custom_properties]
        return nil unless custom_props && custom_props.is_a?(Hash)

        lowercase_keys_and_values(custom_props)
      end

      def is_runtime_evaluation_satisfied?(rollout, context)
        runtime_rule = rollout['runtime_evaluation_rule']
        return true unless runtime_rule

        parameters = get_runtime_parameters(context)
        return false unless parameters

        begin
          rule = lowercase_only_leaf_nodes(runtime_rule)
          result = JsonLogic.apply(rule, parameters)
          !!result
        rescue StandardError => e
          @error_handler.handle(e) if @error_handler
          false
        end
      end
    end
  end
end
