# frozen_string_literal: true

require 'open_feature/sdk'

module Mixpanel
  module OpenFeature
    class Provider
      attr_reader :metadata

      def initialize(flags_provider)
        @flags_provider = flags_provider
        @metadata = ::OpenFeature::SDK::Provider::ProviderMetadata.new(name: 'mixpanel-provider').freeze
      end

      def shutdown
        @flags_provider.shutdown if @flags_provider.respond_to?(:shutdown)
      end

      def fetch_boolean_value(flag_key:, default_value:, evaluation_context: nil)
        resolve(flag_key, default_value, :boolean, evaluation_context)
      end

      def fetch_string_value(flag_key:, default_value:, evaluation_context: nil)
        resolve(flag_key, default_value, :string, evaluation_context)
      end

      def fetch_number_value(flag_key:, default_value:, evaluation_context: nil)
        resolve(flag_key, default_value, :number, evaluation_context)
      end

      def fetch_integer_value(flag_key:, default_value:, evaluation_context: nil)
        resolve(flag_key, default_value, :integer, evaluation_context)
      end

      def fetch_float_value(flag_key:, default_value:, evaluation_context: nil)
        resolve(flag_key, default_value, :float, evaluation_context)
      end

      def fetch_object_value(flag_key:, default_value:, evaluation_context: nil)
        resolve(flag_key, default_value, :object, evaluation_context)
      end

      private

      def resolve(flag_key, default_value, expected_type, evaluation_context)
        unless flags_ready?
          return error_result(default_value, ::OpenFeature::SDK::Provider::ErrorCode::PROVIDER_NOT_READY)
        end

        context = build_context(evaluation_context)
        fallback = ::Mixpanel::Flags::SelectedVariant.new(variant_value: default_value)

        begin
          result = @flags_provider.get_variant(flag_key, fallback, context, report_exposure: true)
        rescue StandardError
          return error_result(default_value, ::OpenFeature::SDK::Provider::ErrorCode::GENERAL)
        end

        if result.equal?(fallback)
          return error_result(default_value, ::OpenFeature::SDK::Provider::ErrorCode::FLAG_NOT_FOUND)
        end

        value = result.variant_value

        coerced = coerce_value(value, expected_type)
        if coerced.nil? && !value.nil?
          return error_result(default_value, ::OpenFeature::SDK::Provider::ErrorCode::TYPE_MISMATCH)
        end

        ::OpenFeature::SDK::Provider::ResolutionDetails.new(
          value: coerced.nil? ? value : coerced,
          variant: result.variant_key,
          reason: ::OpenFeature::SDK::Provider::Reason::STATIC
        )
      end

      def coerce_value(value, expected_type)
        case expected_type
        when :boolean
          value == true || value == false ? value : nil
        when :string
          value.is_a?(String) ? value : nil
        when :integer
          if value.is_a?(Integer)
            value
          elsif value.is_a?(Float) && value.finite? && value == value.floor
            value.to_i
          end
        when :float
          if value.is_a?(Float)
            value
          elsif value.is_a?(Integer)
            value.to_f
          end
        when :number
          value.is_a?(Numeric) ? value : nil
        when :object
          value
        end
      end

      def build_context(evaluation_context)
        return {} if evaluation_context.nil?

        ctx = {}
        if evaluation_context.respond_to?(:fields)
          evaluation_context.fields.each { |k, v| ctx[k] = unwrap_value(v) }
        end
        if evaluation_context.respond_to?(:targeting_key) && evaluation_context.targeting_key
          ctx['targetingKey'] = unwrap_value(evaluation_context.targeting_key)
        end
        ctx
      end

      def unwrap_value(value)
        case value
        when Float
          value.finite? && value == value.floor ? value.to_i : value
        when Array
          value.map { |v| unwrap_value(v) }
        when Hash
          value.transform_values { |v| unwrap_value(v) }
        else
          value
        end
      end

      def flags_ready?
        if @flags_provider.respond_to?(:are_flags_ready)
          @flags_provider.are_flags_ready
        else
          true
        end
      end

      def error_result(default_value, error_code)
        ::OpenFeature::SDK::Provider::ResolutionDetails.new(
          value: default_value,
          error_code: error_code,
          reason: ::OpenFeature::SDK::Provider::Reason::ERROR
        )
      end
    end
  end
end
