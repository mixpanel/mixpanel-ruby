require 'thread'
require 'json_logic'
require 'mixpanel-ruby/flags/flags_provider'
require 'mixpanel-ruby/flags/custom_operators'

module Mixpanel
  module Flags
    # Local feature flags provider
    # Evaluates flags client-side with cached flag definitions
    class LocalFlagsProvider < FlagsProvider
      DEFAULT_CONFIG = {
        api_host: 'api.mixpanel.com',
        request_timeout_in_seconds: 10,
        enable_polling: true,
        polling_interval_in_seconds: 60,
        exposure_executor: nil
      }.freeze

      # The highest context_template_version this SDK knows how to apply.
      SUPPORTED_CONTEXT_TEMPLATE_VERSION = 1

      # A {property} placeholder in a context template.
      CONTEXT_PLACEHOLDER = /\{([^}]+)\}/

      # @param token [String] Mixpanel project token
      # @param config [Hash] Local flags configuration
      # @param tracker_callback [Proc] Callback to track events
      # @param error_handler [Mixpanel::ErrorHandler] Error handler
      # @param credentials [ServiceAccountCredentials, nil] Optional service account credentials
      # @param hierarchical_groups [Boolean] true if the project uses hierarchical
      #   groups (default false). On such a project an exposure event is attributed
      #   by $user_id and $company_id from the context, and tracker_callback receives
      #   a Mixpanel::Identity instead of a distinct_id string.
      def initialize(token, config, tracker_callback, error_handler, credentials = nil, hierarchical_groups: false)
        # compact: an explicit nil from the caller (e.g.
        # polling_interval_in_seconds: nil) must not override a sane default.
        # Both the previous sleep(nil) and the current
        # ConditionVariable#wait(mutex, nil) block indefinitely, which would
        # silently disable polling — fall back to the default instead.
        @config = DEFAULT_CONFIG.merge((config || {}).compact)

        interval = @config[:polling_interval_in_seconds]
        unless interval.is_a?(Numeric) && interval > 0
          raise ArgumentError,
                "polling_interval_in_seconds must be a positive number, got: #{interval.inspect}"
        end

        provider_config = {
          token: token,
          api_host: @config[:api_host],
          request_timeout_in_seconds: @config[:request_timeout_in_seconds],
          exposure_executor: @config[:exposure_executor],
          credentials: credentials,
          hierarchical_groups: hierarchical_groups
        }

        super(provider_config, '/flags/definitions', tracker_callback, 'local', error_handler)

        @flag_definitions = {}
        @polling_thread = nil
        @stop_polling = false
        @polling_mutex = Mutex.new
        @polling_condition = ConditionVariable.new
        # Separate from @polling_mutex: serializes the full start/stop lifecycle
        # (including the join inside stop) so a concurrent start can't observe a
        # mid-stop state and spawn a new polling thread before the old one
        # finishes exiting. We can't hold @polling_mutex across the join — the
        # polling thread needs it to wake from the condition wait.
        @lifecycle_mutex = Mutex.new
      end

      # Start polling for flag definitions
      # Fetches immediately, then at regular intervals if polling enabled
      def start_polling_for_definitions!
        # Clear @stop_polling BEFORE the initial fetch so a concurrent
        # stop_polling_for_definitions! arriving during the fetch can flip it
        # back to true and signal "abandon start". Under @polling_mutex, writes
        # to @stop_polling are linearized: whichever of {start's clear, stop's
        # set} happened latest is what we observe under the lifecycle lock
        # below — i.e. last-writer-wins semantics preserve stop's postcondition
        # (polling is off when stop returns) even across the unguarded fetch.
        @polling_mutex.synchronize { @stop_polling = false }

        # Initial fetch is intentionally outside @lifecycle_mutex: it's a
        # blocking HTTP call, and holding the lifecycle lock across it would
        # block a concurrent stop_polling_for_definitions! for the full request
        # timeout.
        #
        # A transient failure here (network blip, HTTP 500) should NOT prevent
        # the polling thread from spawning — the loop retries on the configured
        # interval. Without this inner rescue, the outer rescue below would
        # catch and return, leaving the SDK permanently without polling until
        # the caller manually retried.
        begin
          fetch_flag_definitions
        rescue StandardError => e
          safe_handle_error(e)
        end

        @lifecycle_mutex.synchronize do
          # If a stop arrived during/after our @stop_polling clear above, abort
          # — the user's stop "wins" because it's the most recent intent.
          stop_requested = @polling_mutex.synchronize { @stop_polling }

          # .alive? guards against a prior polling thread that died abnormally
          # (e.g. error_handler itself raised); without it @polling_thread would
          # be non-nil-but-dead and we'd silently refuse to restart polling.
          if !stop_requested && @config[:enable_polling] &&
             (@polling_thread.nil? || !@polling_thread.alive?)
            @polling_thread = Thread.new do
              loop do
                # Check @stop_polling INSIDE the mutex (before and after wait)
                # so a broadcast from stop_polling_for_definitions! can't be
                # lost if it arrives while we're outside the synchronized region
                # (e.g. during fetch_flag_definitions below).
                stopped = @polling_mutex.synchronize do
                  next true if @stop_polling

                  @polling_condition.wait(@polling_mutex, @config[:polling_interval_in_seconds])
                  @stop_polling
                end
                break if stopped

                begin
                  fetch_flag_definitions
                rescue StandardError => e
                  safe_handle_error(e)
                end
              end
            end
          end
        end
      rescue StandardError => e
        safe_handle_error(e)
      end

      def stop_polling_for_definitions!
        @lifecycle_mutex.synchronize do
          @polling_mutex.synchronize do
            @stop_polling = true
            @polling_condition.broadcast
          end
          @polling_thread&.join
          @polling_thread = nil
        end
      end

      def shutdown
        stop_polling_for_definitions!
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

        return fallback_variant.as_fallback(FallbackReason.flag_not_found) unless flag

        context_key = flag['context']
        context_value = context[context_key] || context[context_key.to_sym]

        # The context value is used as sent. Where the caller did not send it,
        # the service may publish a template saying how to build it from
        # properties they did send; this SDK never composes an identity itself.
        template = flag['context_template']
        template_value = nil
        if context_value.nil? && template && !template.empty?
          template_value = apply_context_template(template, context)
          if template_value.nil?
            return fallback_variant.as_fallback(FallbackReason.missing_context_key(context_key))
          end
          context_value = template_value
        end

        unless template_value || context.key?(context_key) || context.key?(context_key.to_sym)
          return fallback_variant.as_fallback(FallbackReason.missing_context_key(context_key))
        end

        # Test users are keyed by distinct id. When the flag assigns on
        # distinct_id its template builds exactly that.
        templated_distinct_id = context_key == 'distinct_id' ? template_value : nil
        selected_variant = get_variant_override_for_test_user(flag, context, templated_distinct_id)

        unless selected_variant
          rollout = get_assigned_rollout(flag, context_value, context)
          selected_variant = get_assigned_variant(flag, context_value, flag_key, rollout) if rollout
        end

        return fallback_variant.as_fallback(FallbackReason.no_rollout_match) unless selected_variant

        track_exposure_event(flag_key, selected_variant, context) if report_exposure
        selected_variant.with_source(VariantSource::LOCAL)
      end

      # Get all variants for user context
      # Exposure events NOT tracked automatically
      # @param context [Hash] Evaluation context
      # @return [Hash] Map of flag_key => SelectedVariant
      def get_all_variants(context)
        variants = {}
        fallback = SelectedVariant.new(variant_value: nil)

        @flag_definitions.each_key do |flag_key|
          variant = get_variant(flag_key, fallback, context, report_exposure: false)
          variants[flag_key] = variant if variant.variant_source == VariantSource::LOCAL
        end

        variants
      end

      private

      # Wrap @error_handler.handle so a misbehaving handler can't kill the
      # polling thread mid-loop — that would leave @polling_thread non-nil but
      # dead, and (without the .alive? check in start) silently prevent restart.
      #
      # Always warn to stderr as well. The default Mixpanel::ErrorHandler#handle
      # is a no-op, so dispatching only via @error_handler swallows schema drift
      # (NoMethodError, JSON::ParserError, etc.) — the loop runs forever
      # undetected. Matches the convention in mixpanel-python / mixpanel-java /
      # mixpanel-go / mixpanel-node, all of which log unconditionally and keep
      # polling.
      def safe_handle_error(error)
        warn "[Mixpanel] Failed to fetch flag definitions: #{error.class}: #{error.message}"
        @error_handler.handle(error) if @error_handler
      rescue StandardError
        # Swallow handler failures: keeping the polling loop alive is more
        # important than propagating a broken handler's failure.
      end

      def fetch_flag_definitions
        response = call_flags_endpoint

        new_definitions = (response['flags'] || []).each_with_object({}) do |flag_data, definitions|
          # A definition this SDK cannot fully apply is dropped rather than
          # half-evaluated: it would assign a variant the service never chose.
          next unless usable_context_template?(flag_data)
          definitions[flag_data['key']] = flag_data
        end
        @flag_definitions = new_definitions

        response
      end

      # Returns false, with a warning, if the definition's context template is
      # newer than this SDK or has no usable placeholders. A definition without
      # a template is usable.
      def usable_context_template?(flag_data)
        version = flag_data['context_template_version']
        if version.is_a?(Numeric) && version > SUPPORTED_CONTEXT_TEMPLATE_VERSION
          warn "[Mixpanel] Dropping flag '#{flag_data['key']}': context_template_version #{version} is newer " \
               "than this SDK understands (#{SUPPORTED_CONTEXT_TEMPLATE_VERSION}). Evaluate it remotely, or upgrade the SDK."
          return false
        end

        template = flag_data['context_template']
        return true if template.nil? || template == ''

        # Matches {} as well, so that a blank placeholder is caught.
        placeholders = template.to_s.scan(/\{([^}]*)\}/).flatten
        if placeholders.empty? || placeholders.any? { |name| name.strip.empty? }
          warn "[Mixpanel] Dropping flag '#{flag_data['key']}': context_template '#{template}' has no usable placeholders."
          return false
        end

        true
      end

      # Fills a context template the service published with values from the
      # evaluation context. Returns nil when any placeholder's property is
      # missing, nil or empty.
      def apply_context_template(template, context)
        missing = false
        resolved = template.gsub(CONTEXT_PLACEHOLDER) do
          value = context_value(context, Regexp.last_match(1))
          if value.nil? || value.to_s.empty?
            missing = true
            ''
          else
            value.to_s
          end
        end
        missing ? nil : resolved
      end

      def get_variant_override_for_test_user(flag, context, templated_distinct_id = nil)
        test_users = flag.dig('ruleset', 'test', 'users')
        return nil unless test_users

        distinct_id = context['distinct_id'] || context[:distinct_id] || templated_distinct_id
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
        variants = flag.dig('ruleset', 'variants')
        return nil unless variants

        variants.each do |v|
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
        rollouts = flag.dig('ruleset', 'rollout')
        return nil unless rollouts

        rollouts.each_with_index do |rollout, index|
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

        variants = flag['ruleset']['variants'].map(&:dup)
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
          # A well-formed runtime rule evaluates to a boolean. Anything else —
          # notably an unrecognized operator, which the engine echoes back as a
          # (truthy) hash rather than raising — fails closed.
          result == true
        rescue StandardError => e
          @error_handler.handle(e) if @error_handler
          false
        end
      end
    end
  end
end
