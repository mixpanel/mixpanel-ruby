module Mixpanel
  module Flags
    # Selected variant returned from flag evaluation
    class SelectedVariant
      attr_accessor :variant_key, :variant_value, :experiment_id,
                    :is_experiment_active, :is_qa_tester

      # @param variant_key [String, nil] The variant key
      # @param variant_value [Object] The variant value (any type)
      # @param experiment_id [String, nil] Associated experiment ID
      # @param is_experiment_active [Boolean, nil] Whether experiment is active
      # @param is_qa_tester [Boolean, nil] Whether user is a QA tester
      def initialize(variant_key: nil, variant_value: nil, experiment_id: nil,
                     is_experiment_active: nil, is_qa_tester: nil)
        @variant_key = variant_key
        @variant_value = variant_value
        @experiment_id = experiment_id
        @is_experiment_active = is_experiment_active
        @is_qa_tester = is_qa_tester
      end

      # Convert to hash representation
      # @return [Hash]
      def to_h
        {
          variant_key: @variant_key,
          variant_value: @variant_value,
          experiment_id: @experiment_id,
          is_experiment_active: @is_experiment_active,
          is_qa_tester: @is_qa_tester
        }.compact
      end
    end
  end
end
