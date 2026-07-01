# frozen_string_literal: tru

using JsonLogic::Semantics

class JsonLogic::Operations::Some < JsonLogic::EnumerableOperation
  def self.name = "some"

  def call(args, data)
    items, rule_applied_to_each_item = resolve_items_and_per_item_rule(args, data)
    return false if items.empty?

    items.any? do |item|
      !!JsonLogic.apply(rule_applied_to_each_item, item)
    end
  end
end
