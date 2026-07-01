# frozen_string_literal: true

using JsonLogic::Semantics

class JsonLogic::Operations::None < JsonLogic::EnumerableOperation
  def self.name = "none"

  def call(args, data)
    items, rule_applied_to_each_item = resolve_items_and_per_item_rule(args, data)
    items.none? do |item|
      !!(JsonLogic.apply(rule_applied_to_each_item, item))
    end
  end
end
