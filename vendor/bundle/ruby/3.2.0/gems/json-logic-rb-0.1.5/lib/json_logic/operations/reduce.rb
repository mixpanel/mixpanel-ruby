# frozen_string_literal: true

class JsonLogic::Operations::Reduce < JsonLogic::EnumerableOperation
  def self.name = "reduce"

  def call(args, data)
    rule_that_returns_items, step_rule_applied_per_item, rule_that_returns_initial_accumulator = args

    items = Array(JsonLogic.apply(rule_that_returns_items, data))
    acc   = JsonLogic.apply(rule_that_returns_initial_accumulator, data)

    items.reduce(acc) do |memo, item|
      JsonLogic.apply(
        step_rule_applied_per_item,
        (data || {}).merge("" => item, "current" => item, "accumulator" => memo)
      )
    end
  end
end
